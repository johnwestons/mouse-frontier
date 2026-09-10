local Catalog = require("game.catalog")
local CharacterAnimation = require("game.character_animation")
local EventUI = require("game.event_ui")
local Roster = require("game.roster")
local Wildlife = require("game.wildlife") -- retained only for dynamic chickens
local Mice = require("game.mice")
local AssetDiagnostics = require("game.asset_diagnostics")
local LootProgression = require("game.loot_progression")
local FirstPersonWeaponViews = require("game.first_person_weapon_views")
local CrowCaravanArt = require("game.crow_caravan_art")

local Assets = {}
local missingRequired
local lazyPaths=setmetatable({},{__mode="k"})
local lazyCategories=setmetatable({},{__mode="k"})
local externallyOwnedImages=setmetatable({},{__mode="k"})

local function loadImage(path,category)
    local ok, image = pcall(love.graphics.newImage, path)
    if (not ok or not image) and category then AssetDiagnostics.record(path,category,ok and "no image returned" or image) end
    return ok and image or nil
end

local function loadFallback(paths,category)
    for _,path in ipairs(paths) do local image=loadImage(path); if image then return image end end
    AssetDiagnostics.record(table.concat(paths," OR "),category,"all fallback candidates failed")
end

local function prepareLazyImages(destination)
    local paths,categories={},{}; lazyPaths[destination]=paths; lazyCategories[destination]=categories
    setmetatable(destination,{__index=function(self,key)
        local path=paths[key]
        if not path then return nil end
        local image=loadImage(path,categories[key])
        if image then rawset(self,key,image) end
        return image
    end})
end

local function registerLazyImage(destination,key,path,category)
    local paths=lazyPaths[destination]
    if paths then paths[key]=path; lazyCategories[destination][key]=category else destination[key]=loadImage(path,category) end
end

local function releaseLazyImages(destination,keep)
    if not lazyPaths[destination] then return end
    for key,image in pairs(destination) do
        if not (keep and keep[key]) and not externallyOwnedImages[image] then
            if image and image.release then pcall(image.release,image) end
            rawset(destination,key,nil)
        end
    end
end

local function requireImage(path)
    local image = loadImage(path,"required")
    if not image and missingRequired then missingRequired[#missingRequired + 1] = path end
    return image
end

local function loadFolderImages(path, destination, predicate, category)
    if not love.filesystem.getInfo(path) then return end
    for _, file in ipairs(love.filesystem.getDirectoryItems(path)) do
        if file:match("%.png$") and (not predicate or predicate(file)) then
            destination[file:gsub("%.png$", "")] = loadImage(path .. "/" .. file,category)
        end
    end
end

local function registerItemAtlas(ui, path, names, columns, rows, clearGeneratedChecker)
    local image
    if clearGeneratedChecker and love.image and love.image.newImageData then
        local ok,data=pcall(love.image.newImageData,path)
        if ok and data then
            data:mapPixel(function(_,_,r,g,b,a)
                local pale=math.min(r,g,b)>.89 and math.max(r,g,b)-math.min(r,g,b)<.045
                return r,g,b,pale and 0 or a
            end)
            local made,result=pcall(love.graphics.newImage,data)
            if made then image=result end
        end
    end
    image=image or loadImage(path,"item atlas")
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

local function loadGeneratedAnimationAtlas(path, columns, rows, count)
    local ok,data=pcall(love.image.newImageData,path)
    if not ok or not data then
        AssetDiagnostics.record(path,"mob animation","could not decode generated atlas")
        return nil
    end
    -- Some generator results contain their transparent-preview checker as RGB.
    -- Sludges have no near-white neutral colors, so this narrowly removes that
    -- preview surface while preserving their black, yellow, and cyan palette.
    data:mapPixel(function(_,_,r,g,b,a)
        if a<.065 then return r,g,b,0 end
        local neutral=math.max(r,g,b)-math.min(r,g,b)<.045
        if neutral and math.min(r,g,b)>.89 then return r,g,b,0 end
        return r,g,b,a
    end)
    local made,image=pcall(love.graphics.newImage,data)
    if not made or not image then
        AssetDiagnostics.record(path,"mob animation","could not create generated atlas image")
        return nil
    end
    image:setFilter("nearest","nearest")
    local width,height=image:getDimensions()
    if width%columns~=0 or height%rows~=0 then
        AssetDiagnostics.record(path,"mob animation","atlas dimensions do not match its grid")
        return nil
    end
    return {image=image,columns=columns,rows=rows,count=count or columns*rows,
        w=width/columns,h=height/rows,path=path}
end

local function loadGridAtlas(path, columns, rows, category)
    local image=loadImage(path,category)
    if not image then return nil end
    image:setFilter("nearest","nearest")
    local width,height=image:getDimensions()
    if columns<1 or rows<1 or width%columns~=0 or height%rows~=0 then
        AssetDiagnostics.record(path,category,"atlas dimensions do not divide into its frame grid")
        return nil
    end
    local frameWidth,frameHeight=width/columns,height/rows
    local atlas={image=image,count=columns*rows,w=frameWidth,h=frameHeight,columns=columns,rows=rows,quads={}}
    for index=1,atlas.count do
        local column,row=(index-1)%columns,math.floor((index-1)/columns)
        atlas.quads[index]=love.graphics.newQuad(column*frameWidth,row*frameHeight,frameWidth,frameHeight,width,height)
    end
    return atlas
end

local function loadHorizontalAtlas(path, count, category)
    return loadGridAtlas(path,count,1,category)
end

local function loadVerticalAtlas(path, count, category)
    local image=loadImage(path,category)
    if not image then return nil end
    image:setFilter("nearest","nearest")
    local width,height=image:getDimensions()
    if count<1 or height%count~=0 then
        AssetDiagnostics.record(path,category,"atlas height does not divide into its frame count")
        return nil
    end
    local frameHeight=height/count
    local atlas={image=image,count=count,w=width,h=frameHeight,quads={}}
    for index=1,count do
        atlas.quads[index]=love.graphics.newQuad(0,(index-1)*frameHeight,width,frameHeight,width,height)
    end
    return atlas
end

local function loadAlphaCutoffShader()
    local ok,shader=pcall(love.graphics.newShader,[=[
        vec4 effect(vec4 color, Image texture, vec2 textureCoordinates, vec2 screenCoordinates) {
            vec4 pixel = Texel(texture, textureCoordinates);
            if (pixel.a < 0.125) discard;
            return pixel * color;
        }
    ]=])
    if not ok then
        AssetDiagnostics.record("generated-alpha-cutoff","train scenery",shader)
        return nil
    end
    return shader
end

local function addHorizontalAtlasSlice(atlas,name,sourceY,height)
    if not atlas then return end
    local imageWidth,imageHeight=atlas.image:getDimensions()
    assert(sourceY>=0 and height>0 and sourceY+height<=imageHeight,"invalid atlas slice")
    local quads={}
    for index=1,atlas.count do
        quads[index]=love.graphics.newQuad((index-1)*atlas.w,sourceY,atlas.w,height,imageWidth,imageHeight)
    end
    atlas[name]={quads=quads,sourceY=sourceY,h=height}
end

local function validateCatalogArt(ui)
    local checked = {}
    local virtual = {scratch=true, ["mob-claw"]=true, ["mob-spit"]=true}
    local function requireNamed(name, category)
        if not name or checked[name] or virtual[name] then return end
        checked[name] = true
        local registered=(rawget(ui.propImages,name)~=nil) or (lazyPaths[ui.propImages] and lazyPaths[ui.propImages][name]~=nil)
        if not registered and not ui.atlasItems[name] then
            AssetDiagnostics.record("catalog:" .. name, category, "no standalone sprite or atlas entry")
        end
    end
    local function requireKeys(values, category)
        for name in pairs(values or {}) do requireNamed(name, category) end
    end
    local function requireList(values, category)
        for _, name in ipairs(values or {}) do requireNamed(name, category) end
    end

    requireKeys(Catalog.weaponStats, "catalog weapon")
    requireKeys(Catalog.itemEffects, "catalog item")
    requireKeys(Catalog.backpackUpgrades, "catalog backpack")
    requireKeys(Catalog.storageCapacities, "catalog furniture")
    requireKeys(Catalog.ammoPickupAmounts, "catalog ammunition")
    requireList(Catalog.questRewardItems, "catalog quest reward")
    for _, pool in pairs(Catalog.lootPools or {}) do requireList(pool, "catalog loot") end
    local progressionOk,progressionErrors=LootProgression.validate(Catalog)
    if not progressionOk then for _,message in ipairs(progressionErrors) do AssetDiagnostics.record("loot-progression","catalog progression",message) end end
end

local function loadBattleAtlas(file, label)
    local image = loadImage("assets/sprites/battle-maps/" .. file,"battle scenery")
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

local function loadGeneratedBattleAtlas(file)
    local path="assets/sprites/battle-maps/"..file
    local ok,data=pcall(love.image.newImageData,path)
    if not ok or not data then AssetDiagnostics.record("battle scenery",path,"could not decode generated obstacle atlas"); return nil end
    -- The built-in generator preserved its preview checker in RGB. Convert
    -- only its bright neutral squares to alpha at load so the approved pixel
    -- art remains portable in the tracked source image.
    data:mapPixel(function(_,_,r,g,b,a)
        local neutral=math.max(r,g,b)-math.min(r,g,b)<.035
        if neutral and math.min(r,g,b)>.82 then return r,g,b,0 end
        return r,g,b,a
    end)
    local image=love.graphics.newImage(data); image:setFilter("nearest","nearest")
    local width,height=image:getDimensions(); local cellWidth,cellHeight=width/3,height/2
    local atlas={image=image,cw=cellWidth,ch=cellHeight,quads={}}
    for index=1,6 do local column,row=(index-1)%3,math.floor((index-1)/3); atlas.quads[index]=love.graphics.newQuad(column*cellWidth,row*cellHeight,cellWidth,cellHeight,width,height) end
    return atlas
end

local function loadMenuFrames(ui)
    ui.menuFrames = {}
    for index, file in ipairs({"train-dialog-frame-v1.png", "train-panel-frame-v1.png", "train-tooltip-frame-v1.png", "train-button-frame-v1.png"}) do
        local image = loadImage("assets/sprites/ui/" .. file,"UI")
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
    AssetDiagnostics.reset()
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
    prepareLazyImages(npcImages); prepareLazyImages(mobImages)

    ui.radioFace = loadImage("assets/sprites/ui/radio/radio-gui.png","UI")
    ui.radioButtonsImage = loadImage("assets/sprites/ui/radio/radio-buttons.png","UI")
    if ui.radioButtonsImage then
        local imageWidth, imageHeight = ui.radioButtonsImage:getDimensions()
        ui.radioButtonQuads = {}
        for index = 1, 3 do
            ui.radioButtonQuads[index] = love.graphics.newQuad((index - 1) * imageWidth / 3, 0, imageWidth / 3, imageHeight, imageWidth, imageHeight)
        end
    end
    ui.objectTintShader = loadShader()
    scenery.titleImage = loadImage("assets/sprites/ui/title/title-option-3.png", "UI")
    scenery.introBackground = loadImage("assets/backgrounds/intro/train-journey-sunrise.png", "UI")
    scenery.introLocomotive = loadImage("assets/sprites/train/cinematic-locomotive.png", "UI")
    scenery.introLocomotiveSheet = loadImage("assets/sprites/train/cinematic-locomotive-run-10-v2.png", "UI")
    scenery.introCars = loadImage("assets/sprites/train/cinematic-five-car-consist.png", "UI")

    for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/MainCharacters")) do
        if Roster.isPlayable(file) then
            characters[#characters + 1] = file
            characterImages[file] = requireImage("assets/sprites/MainCharacters/" .. file)
        end
    end
    table.sort(characters)

    local backgroundFiles = love.filesystem.getDirectoryItems("assets/backgrounds")
    for _, file in ipairs(backgroundFiles) do
        local index=file:match("^stop%-(%d%d)")
        if index then
            index=tonumber(index)
            targets.backgroundImages[index]=loadImage("assets/backgrounds/" .. file,"scenery")
        end
    end

    scenery.fire = loadImage("assets/sprites/characters/fire-spirit.png","train scenery")
    scenery.fireFrames = {scenery.fire, loadImage("assets/sprites/characters/animations/fire-spirit-idle-2.png","train scenery"), scenery.fire, loadImage("assets/sprites/characters/animations/fire-spirit-idle-3.png","train scenery")}
    scenery.boiler = loadImage("assets/sprites/train-decorations/boiler-firebox.png","train scenery")
    scenery.curtain = loadFallback({"assets/sprites/train-decorations/train-window-curtain.png","assets/sprites/train-decorations/porthole-curtain.png"},"train scenery")
    scenery.smokeLarge1 = loadImage("assets/sprites/train-decorations/locomotive-smoke-large-1.png","train scenery")
    scenery.smokeLarge2 = loadImage("assets/sprites/train-decorations/locomotive-smoke-large-2.png","train scenery")
    scenery.smokeSmall = loadImage("assets/sprites/train-decorations/locomotive-smoke-small.png","train scenery")
    scenery.cloudImages = {}
    for _, file in ipairs({"cloud-1.png", "cloud-2.png", "cloud-3.png", "cloud-4.png", "cloud-5.png", "cloud-6.png", "cloud-7.png", "cloud-8.png", "cloud-9.png"}) do
        scenery.cloudImages[#scenery.cloudImages + 1] = loadImage("assets/sprites/effects/clouds/" .. file,"sky effects")
    end

    for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/MainCharacters/animations")) do
        if file:match("%-walk%.png$") and not file:match("%-left%.png$") and not file:match("%-right%.png$") then
            registerLazyImage(characterWalkImages,file:gsub("%-walk%.png$", ".png"),"assets/sprites/MainCharacters/animations/" .. file)
        elseif file:match("%-action%.png$") then
            registerLazyImage(characterActionImages,file:gsub("%-action%.png$", ".png"),"assets/sprites/MainCharacters/animations/" .. file)
        end
    end

    scenery.homeTexture = loadImage("assets/textures/home-interior-floor.png","interior scenery")
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
    scenery.trainTexture = loadImage("assets/textures/train-interior-panels.png","train scenery")

    for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/NPCS")) do
        if Roster.isNpcCandidate(file) then registerLazyImage(npcImages,file,"assets/sprites/NPCS/" .. file,"NPC") end
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
            registerLazyImage(mobImages,file,"assets/sprites/Mobs/" .. file,"mob")
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
    local sludgeAtlasRoot="assets/sprites/Mobs/atlases/"
    local sludgeIdleWalk=loadGeneratedAnimationAtlas(sludgeAtlasRoot.."sludge-crawler-mouse-ears-idle-walk.png",2,2,4)
    scenery.sludgeAnimations={
        idle=sludgeIdleWalk,
        walk=sludgeIdleWalk,
        attack=loadGeneratedAnimationAtlas(sludgeAtlasRoot.."sludge-crawler-mouse-ears-attack.png",2,2,4),
        hit=loadGeneratedAnimationAtlas(sludgeAtlasRoot.."sludge-crawler-mouse-ears-hit.png",2,2,4),
        death=loadGeneratedAnimationAtlas(sludgeAtlasRoot.."sludge-crawler-mouse-ears-death.png",2,2,4),
    }
    scenery.firstAidAssets={
        wound=requireImage("assets/sprites/props/first-aid/small-cut.png"),
        disinfectant=requireImage("assets/sprites/props/first-aid/disinfectant-bottle.png"),
        rag=requireImage("assets/sprites/props/first-aid/clean-rag.png"),
        swab=requireImage("assets/sprites/props/first-aid/ointment-swab.png"),
        gauze=requireImage("assets/sprites/props/first-aid/gauze-pad.png"),
        bandage=requireImage("assets/sprites/props/first-aid/bandage-roll.png"),
        bandageStrips={
            requireImage("assets/sprites/props/first-aid/bandage-strip.png"),
            requireImage("assets/sprites/props/first-aid/bandage-strip-2.png"),
            requireImage("assets/sprites/props/first-aid/bandage-strip-3.png"),
        },
    }
    local shootingRangeWeaponViews=FirstPersonWeaponViews.new(
        function(path) return loadImage(path,"shooting range weapon") end,
        function(path) return love.filesystem.getInfo(path)~=nil end)
    scenery.shootingRangeAssets={
        background=requireImage("assets/sprites/props/shooting-range/range-background.png"),
        targets=requireImage("assets/sprites/props/shooting-range/target-atlas.png"),
        impacts=requireImage("assets/sprites/props/shooting-range/impact-atlas.png"),
        entrance=requireImage("assets/sprites/props/shooting-range/range-trail-flag-atlas.png"),
        weaponViews=shootingRangeWeaponViews,
    }
    local caravanRoot="assets/sprites/caravans/rookery/"
    local caravanCampfirePath=caravanRoot.."animations/campfire-idle-4-v1.png"
    local caravanCampfire=loadHorizontalAtlas(caravanCampfirePath,4,"required")
    if not caravanCampfire then missingRequired[#missingRequired+1]=caravanCampfirePath end
    local caravanStallPath=caravanRoot.."animations/merchant-stall-breeze-4-v1.png"
    local caravanStallImage=requireImage(caravanStallPath)
    local caravanStall=caravanStallImage and CrowCaravanArt.stallAtlas(caravanStallImage,love.graphics.newQuad)
    scenery.crowCaravanAssets={
        background=requireImage("assets/backgrounds/crow-caravan-campsite-v1.png"),
        wagonBody=requireImage(caravanRoot.."wagon-body-v1.png"),
        wagonWheel=requireImage(caravanRoot.."wagon-wheel-v1.png"),
        stallBody=requireImage(caravanRoot.."merchant-stall-body-v2.png"),
        stallBreeze=caravanStall,
        patchedTent=requireImage(caravanRoot.."patched-tent-v1.png"),
        cargoCluster=requireImage(caravanRoot.."cargo-cluster-v1.png"),
        crowBanner=requireImage(caravanRoot.."crow-banner-v1.png"),
        campfire=caravanCampfire,
    }
    -- Short semantic names are the area renderer's public bundle contract;
    -- keep the descriptive aliases above useful to diagnostics and tools.
    scenery.crowCaravanAssets.wheel=scenery.crowCaravanAssets.wagonWheel
    scenery.crowCaravanAssets.tent=scenery.crowCaravanAssets.patchedTent
    scenery.crowCaravanAssets.cargo=scenery.crowCaravanAssets.cargoCluster
    if love.filesystem.getInfo("assets/sprites/NPCS/families") then
        loadFolderImages("assets/sprites/NPCS/families", targets.familyImages,nil,"family character")
    end
    table.sort(mobFiles)

    ui.propImages = {}; prepareLazyImages(ui.propImages)
    for _, path in ipairs({"assets/sprites/props", "assets/sprites/items", "assets/sprites/furniture", "assets/sprites/weapons", "assets/sprites/train-decorations", "assets/sprites/ammo", "assets/sprites/gear"}) do
        if love.filesystem.getInfo(path) then for _,file in ipairs(love.filesystem.getDirectoryItems(path)) do if file:match("%.png$") then registerLazyImage(ui.propImages,file:gsub("%.png$", ""),path.."/"..file,"item/furniture/weapon") end end end
    end
    targets.itemIdleImages["flower-pot"] = {ui.propImages["flower-pot"], loadImage("assets/sprites/items/animations/flower-pot-idle-2.png"), loadImage("assets/sprites/items/animations/flower-pot-idle-3.png")}

    ui.atlasItems = {}
    registerItemAtlas(ui, "assets/sprites/atlases/food-water-v1.png", {"trail-beans-can", "dried-berry-pouch", "cornbread-square", "mushroom-stew", "jerky-bundle", "preserved-peaches", "metal-water-flask", "blue-water-bottle", "rainwater-jar", "patched-canteen", "boxed-fruit-drink", "ceramic-water-crock"}, 4, 3)
    registerItemAtlas(ui, "assets/sprites/atlases/firearms-v1.png", {"compact-scrap-pistol", "long-barrel-22-pistol", "heavy-frontier-pistol", "machine-pistol", "weathered-lever-rifle", "improvised-service-rifle", "compact-carbine", "rugged-submachine-gun"}, 4, 2)
    registerItemAtlas(ui, "assets/sprites/atlases/melee-frontier-v1.png", {"salvage-pry-bar", "frontier-hook-sickle", "boiler-smith-maul", "railway-war-pick"}, 2, 2, true)
    registerItemAtlas(ui, "assets/sprites/atlases/melee-blades-v1.png", {"patched-trench-knife", "gear-toothed-falchion", "railway-cutlass", "brass-backed-greatsword"}, 2, 2)
    registerItemAtlas(ui, "assets/sprites/atlases/melee-polearms-v1.png", {"scrap-hunting-spear", "frontier-fork-trident", "hooked-railway-halberd", "wasteland-partisan"}, 2, 2, true)
    registerItemAtlas(ui, "assets/sprites/atlases/melee-axes-v1.png", {"salvaged-track-hatchet", "gearwright-bearded-axe", "rail-splitter-axe", "frontier-executioner-axe"}, 2, 2)
    registerItemAtlas(ui, "assets/sprites/gear/backpack-upgrades-v1.png", {"patched-canvas-pack", "bedroll-hiking-pack", "frontier-leather-pack", "scavenger-frame-pack"}, 2, 2)
    validateCatalogArt(ui)
    loadMenuFrames(ui)

    -- The old independently redrawn locomotives are retained only for their
    -- transparent smoke area. The approved boiler/cab/tender body is invariant;
    -- wheels and rods are now composed over it by the train renderer.
    scenery.worldTrainSmokeFrames = {}
    for index = 1, 3 do
        local image = loadImage("assets/sprites/train/animations/locomotive-red-run-" .. index .. ".png","train scenery")
        if image then
            local imageWidth,imageHeight=image:getDimensions()
            scenery.worldTrainSmokeFrames[index]={image=image,
                quad=love.graphics.newQuad(0,0,imageWidth,math.min(225,imageHeight),imageWidth,imageHeight)}
        end
    end
    scenery.redTrain = loadImage("assets/sprites/train/locomotive-red.png","train scenery")
    scenery.worldTrain = scenery.redTrain
    scenery.generatedAlphaCutoffShader = loadAlphaCutoffShader()
    scenery.worldTrainBody = loadImage("assets/sprites/train/animations/locomotive-red-body-v2.png","train scenery")
    local runningGearImage=loadImage(
        "assets/sprites/train/animations/locomotive-running-gear-components-v1.png","train scenery")
    if runningGearImage then
        local gearWidth,gearHeight=runningGearImage:getDimensions()
        local function component(x,y,w,h,originX,originY,length)
            return {quad=love.graphics.newQuad(x,y,w,h,gearWidth,gearHeight),
                originX=originX,originY=originY,length=length}
        end
        scenery.worldTrainRunningGear={image=runningGearImage,
            largeWheel=component(130,40,560,560,282,281),
            smallWheel=component(950,160,380,380,192,193),
            couplingRod=component(130,690,520,170,65,87,378),
            connectingRod=component(790,650,720,210,634,116,558),
            jointPin=component(1070,830,170,140,82,67)}
    end
    scenery.trainCarImages = {}
    for _, entry in ipairs(Catalog.trainCarCatalog) do
        scenery.trainCarImages[entry.id] = loadImage("assets/sprites/train/cars/" .. entry.id .. ".png","train scenery")
    end
    scenery.trainCarImages["living-car"] = loadImage("assets/sprites/train/cars/living-car.png","train scenery")
    scenery.trainCarBogie = loadHorizontalAtlas(
        "assets/sprites/train/animations/train-car-bogie-run-4-v1.png",4,"train scenery")
    scenery.track = loadImage("assets/sprites/tracks/railway-track-v2.png","train scenery")
    scenery.ballastPocketFrames = loadVerticalAtlas(
        "assets/sprites/tracks/railway-ballast-pocket-run-4-v1.png",4,"train scenery")

    local projectileImage = loadImage("assets/sprites/projectiles/projectiles-packed-v1.png","battle scenery")
    if projectileImage then
        local imageWidth, imageHeight = projectileImage:getDimensions()
        local cellWidth = imageWidth / 5
        scenery.projectiles = {image = projectileImage, w = cellWidth, h = imageHeight, quads = {}}
        for index = 1, 5 do scenery.projectiles.quads[index] = love.graphics.newQuad((index - 1) * cellWidth, 0, cellWidth, imageHeight, imageWidth, imageHeight) end
    end

    local groundImage = loadImage("assets/sprites/ground/stop-ground-textures-v1.png","scenery")
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
    scenery.battleAccents={}
    for index,entry in ipairs({{"WASTELAND","wasteland-tiles-v4.png"},{"FOREST","forest-tiles-v3.png"},{"TOWN RUINS","town-ruins-tiles-v3.png"},{"MOUNTAINS","mountain-tiles-v3.png"}}) do
        local atlas=loadGeneratedBattleAtlas(entry[2])
        if atlas then atlas.name=entry[1] end
        scenery.battleAccents[index]=atlas
    end
    scenery.battleObstacles=loadGeneratedBattleAtlas("battle-obstacles-v1.png")

    -- Settlement sprites now provide the complete stop surface and buildings.
    -- Keep only chicken assets from the wildlife module for future dynamic spawns.
    scenery.stopWildlife, scenery.stopWildlifeFeeding = {}, {}
    loadFolderImages("assets/sprites/stop-wildlife", scenery.stopWildlife, function(file) return not file:find("atlas") end,"wildlife")
    Wildlife.load(scenery.stopWildlife, function(path) return loadImage(path,"wildlife") end)
    Mice.load(scenery.stopWildlife, function(path) return loadImage(path,"wildlife") end)
    scenery.eventArt = EventUI.load(function(path) return loadImage(path,"event UI") end)
    if love.filesystem.getInfo("assets/sprites/stop-wildlife/animations") then
        for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/stop-wildlife/animations")) do
            local name = file:match("^(.-)%-feed%.png$")
            if name then scenery.stopWildlifeFeeding[name] = loadImage("assets/sprites/stop-wildlife/animations/" .. file,"wildlife") end
        end
    end

    if #missingRequired > 0 then
        error("Required image assets failed to load:\n" .. table.concat(missingRequired, "\n"))
    end
    if AssetDiagnostics.count() > 0 then
        print("[ASSETS] " .. AssetDiagnostics.count() .. " art contract failure(s) detected:\n" .. AssetDiagnostics.summary())
    end
    missingRequired = nil
    return CharacterAnimation.load("assets/sprites/character-animations", loadImage)
end

function Assets.assertHealthy() return AssetDiagnostics.assertHealthy() end
function Assets.assetFailureSummary() return AssetDiagnostics.summary() end
function Assets.assetFailureCount() return AssetDiagnostics.count() end

-- Runtime-generated sprite frames can be shared with the legacy animation
-- tables without transferring their lifetime to the generic lazy streamer.
-- Their owner retains both the image and these registrations until it replaces
-- or explicitly releases them; the registry itself does not keep images alive.
function Assets.markExternallyOwned(image)
    if image then externallyOwnedImages[image]=true end
    return image
end

function Assets.retainAnimationImages(tables,keep)
    for _,images in ipairs(tables or {}) do releaseLazyImages(images,keep) end
end

return Assets
