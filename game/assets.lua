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
local OutfitItemArt = require("game.outfit_item_art")
local LazyGroups = require("game.lazy_asset_groups")
local LastStandLife = require("game.coop_last_stand_lifecycle")

local Assets = {}
local missingRequired
local lazyPaths=setmetatable({},{__mode="k"})
local lazyCategories=setmetatable({},{__mode="k"})
local externallyOwnedImages=setmetatable({},{__mode="k"})
local residentGroups=setmetatable({},{__mode="k"})
local residentTargets=setmetatable({},{__mode="k"})
local itemAtlasCaches=setmetatable({},{__mode="k"})

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

local function registerRequiredLazyImage(destination,key,path)
    if not love.filesystem.getInfo(path) and missingRequired then
        missingRequired[#missingRequired+1]=path
    end
    registerLazyImage(destination,key,path,"required")
end

local function releaseLazyImages(destination,keep)
    local paths=lazyPaths[destination]
    if not paths then return end
    for key in pairs(paths) do
        local image=rawget(destination,key)
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
    local caches=itemAtlasCaches[ui]
    if not caches then caches={};itemAtlasCaches[ui]=caches end
    local cache={records={}};caches[#caches+1]=cache
    local function load()
        if cache.image then return end
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
                if data.release then data:release() end
            end
        end
        image=image or loadImage(path,"item atlas")
        if not image then return end
        cache.image=image
        local imageWidth, imageHeight = image:getDimensions()
        local cellWidth, cellHeight = imageWidth / columns, imageHeight / rows
        for index, name in ipairs(names) do
            local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
            local record=cache.records[index]
            rawset(record,"image",image)
            rawset(record,"quad",love.graphics.newQuad(column * cellWidth,row * cellHeight,cellWidth,cellHeight,imageWidth,imageHeight))
            rawset(record,"w",cellWidth);rawset(record,"h",cellHeight)
        end
    end
    -- Records stay enumerable for the item catalog without decoding a sheet.
    for index,name in ipairs(names)do
        local record={}
        setmetatable(record,{__index=function(self,key)load();return rawget(self,key)end})
        cache.records[index]=record;ui.atlasItems[name]=record
    end
end

local function releaseItemAtlases(ui)
    for _,cache in ipairs(itemAtlasCaches[ui] or {})do
        if cache.image then
            if cache.image.release then cache.image:release()end
            cache.image=nil
            for _,record in ipairs(cache.records)do
                local quad=rawget(record,"quad");if quad and quad.release then quad:release()end
                for _,key in ipairs({"image","quad","w","h"})do rawset(record,key,nil)end
            end
        end
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
    if data.release then data:release() end
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
        if not registered and not ui.atlasItems[name] and not OutfitItemArt.has(name) then
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
    requireKeys(Catalog.rangeTools, "catalog range tool")
    requireKeys(Catalog.miscItems, "catalog miscellaneous item")
    requireKeys(Catalog.backpackUpgrades, "catalog backpack")
    requireKeys(Catalog.wearableItems, "catalog wearable")
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
    local made,image=pcall(love.graphics.newImage,data)
    if data.release then data:release() end
    if not made or not image then AssetDiagnostics.record(path,"battle scenery","could not create generated atlas image"); return nil end
    image:setFilter("nearest","nearest")
    local width,height=image:getDimensions(); local cellWidth,cellHeight=width/3,height/2
    local atlas={image=image,cw=cellWidth,ch=cellHeight,quads={}}
    for index=1,6 do local column,row=(index-1)%3,math.floor((index-1)/3); atlas.quads[index]=love.graphics.newQuad(column*cellWidth,row*cellHeight,cellWidth,cellHeight,width,height) end
    return atlas
end

-- Keep only the active biome's atlases on the GPU. Loading every biome at
-- startup can exhaust memory before the title screen appears on small phones.
local function streamBattleAtlases(entries, loader)
    local activeIndex
    local images={}
    function images:release()
        if not activeIndex then return end
        local previous=rawget(self,activeIndex)
        if previous and previous.image and previous.image.release then
            pcall(previous.image.release,previous.image)
        end
        rawset(self,activeIndex,nil)
        activeIndex=nil
    end
    return setmetatable(images, {__index=function(images,index)
        local entry=type(index)=="number" and entries[index] or nil
        if not entry then return nil end
        if activeIndex and activeIndex~=index then images:release() end
        local atlas=loader(entry)
        if atlas then rawset(images,index,atlas); activeIndex=index end
        return atlas
    end})
end

local function streamWorldBackgrounds(images,paths,loader)
    local activeIndex
    function images:release()
        if not activeIndex then return end
        local previous=rawget(self,activeIndex)
        if previous and previous.release then pcall(previous.release,previous) end
        rawset(self,activeIndex,nil)
        activeIndex=nil
    end
    return setmetatable(images,{__index=function(cache,index)
        local path=type(index)=="number" and paths[index] or nil
        if not path then return nil end
        if activeIndex and activeIndex~=index then cache:release() end
        local image=loader(path)
        if image then rawset(cache,index,image); activeIndex=index end
        return image
    end})
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
    ui.resourceIcons = {}
    for _, name in ipairs({"food", "water", "coal", "oil"}) do
        local image = requireImage("assets/sprites/ui/resources/" .. name .. "-v1.png")
        if image then image:setFilter("nearest", "nearest") end
        ui.resourceIcons[name] = image
    end
    local characters, characterImages = targets.characters, targets.characterImages
    prepareLazyImages(characterImages)
    prepareLazyImages(targets.familyImages)
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
    prepareLazyImages(scenery)
    local sceneAssets=LazyGroups.new(scenery)
    residentGroups[scenery]={scene=sceneAssets}
    residentTargets[scenery]=targets
    local function sceneImage(key,path,group,category)
        sceneAssets:add(key,group,function()return loadImage(path,category or "scenery")end)
    end
    registerLazyImage(scenery,"titleImage","assets/sprites/ui/title/title-option-3.png","UI")
    registerLazyImage(scenery,"titleHeaderBackdrop","assets/sprites/ui/title/title-header-backdrop-v1.png","title UI")
    registerLazyImage(scenery,"titleFooterBackdrop","assets/sprites/ui/title/title-footer-backdrop-v1.png","title UI")
    local titleSnapshotNames={"share-water","share-food","bandage","laugh","help-walk","handshake","seedling-care","share-shelter","radio-repair","warm-kettle","shared-haul","lantern-melody","route-map","herbal-delivery","roadside-repair","quiet-garden","camp-supper","lantern-repair","shared-bandages","fair-trade","boiler-repair","river-route","trailmarkers","signal-lesson","station-map"}
    scenery.titleSnapshotSprites=setmetatable({}, {__index=function(_,id)
        for _,name in ipairs(titleSnapshotNames) do
            if name==id then return scenery["titleSnapshot_"..name] end
        end
        return nil
    end})
    for _,name in ipairs(titleSnapshotNames) do
        registerLazyImage(scenery,"titleSnapshot_"..name,"assets/sprites/ui/title/snapshots/"..name..".png","title UI")
    end
    for name,path in pairs({introBackground="assets/backgrounds/intro/train-journey-sunrise.png",
        introLocomotive="assets/sprites/train/cinematic-locomotive.png",
        introLocomotiveSheet="assets/sprites/train/cinematic-locomotive-run-10-v2.png",
        introCars="assets/sprites/train/cinematic-five-car-consist.png"}) do
        registerLazyImage(scenery,name,path,"UI")
    end

    for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/MainCharacters")) do
        if Roster.isPlayable(file) then
            characters[#characters + 1] = file
            registerRequiredLazyImage(characterImages,file,"assets/sprites/MainCharacters/" .. file)
        end
    end
    table.sort(characters)

    local backgroundFiles = love.filesystem.getDirectoryItems("assets/backgrounds")
    local backgroundPaths={}
    streamWorldBackgrounds(targets.backgroundImages,backgroundPaths,function(path) return loadImage(path,"scenery") end)
    for _, file in ipairs(backgroundFiles) do
        local index=file:match("^stop%-(%d%d)")
        if index then
            index=tonumber(index)
            backgroundPaths[index]="assets/backgrounds/" .. file
            targets.backgroundImages.count=math.max(targets.backgroundImages.count or 0,index)
        end
    end

    sceneImage("fire","assets/sprites/characters/fire-spirit.png","train","train scenery")
    sceneAssets:add("fireFrames","train",function()return {scenery.fire,loadImage("assets/sprites/characters/animations/fire-spirit-idle-2.png","train scenery"),scenery.fire,loadImage("assets/sprites/characters/animations/fire-spirit-idle-3.png","train scenery")}end)
    sceneImage("boiler","assets/sprites/train-decorations/boiler-firebox.png","train","train scenery")
    sceneAssets:add("curtain","train",function()return loadFallback({"assets/sprites/train-decorations/train-window-curtain.png","assets/sprites/train-decorations/porthole-curtain.png"},"train scenery")end)
    sceneImage("smokeLarge1","assets/sprites/train-decorations/locomotive-smoke-large-1.png","train","train scenery")
    sceneImage("smokeLarge2","assets/sprites/train-decorations/locomotive-smoke-large-2.png","train","train scenery")
    sceneImage("smokeSmall","assets/sprites/train-decorations/locomotive-smoke-small.png","train","train scenery")
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

    sceneImage("homeTexture","assets/textures/home-interior-floor.png","home","interior scenery")
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
    sceneImage("trainTexture","assets/textures/train-interior-panels.png","train","train scenery")

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
    sceneAssets:add("sludgeAnimations","stop",function()
      local sludgeIdleWalk=loadGeneratedAnimationAtlas(sludgeAtlasRoot.."sludge-crawler-mouse-ears-idle-walk.png",2,2,4)
      return {
        idle=sludgeIdleWalk,
        walk=sludgeIdleWalk,
        attack=loadGeneratedAnimationAtlas(sludgeAtlasRoot.."sludge-crawler-mouse-ears-attack.png",2,2,4),
        hit=loadGeneratedAnimationAtlas(sludgeAtlasRoot.."sludge-crawler-mouse-ears-hit.png",2,2,4),
        death=loadGeneratedAnimationAtlas(sludgeAtlasRoot.."sludge-crawler-mouse-ears-death.png",2,2,4),
      }
    end)
    scenery.firstAidAssets={bandageStrips={}}
    prepareLazyImages(scenery.firstAidAssets)
    prepareLazyImages(scenery.firstAidAssets.bandageStrips)
    for name,file in pairs({wound="small-cut.png",disinfectant="disinfectant-bottle.png",
        rag="clean-rag.png",swab="ointment-swab.png",gauze="gauze-pad.png",
        bandage="bandage-roll.png"}) do
        registerRequiredLazyImage(scenery.firstAidAssets,name,"assets/sprites/props/first-aid/"..file)
    end
    for index,file in ipairs({"bandage-strip.png","bandage-strip-2.png","bandage-strip-3.png"}) do
        registerRequiredLazyImage(scenery.firstAidAssets.bandageStrips,index,"assets/sprites/props/first-aid/"..file)
    end
    local shootingRangeWeaponViews=FirstPersonWeaponViews.new(
        function(path) return loadImage(path,"shooting range weapon") end,
        function(path) return love.filesystem.getInfo(path)~=nil end,
        function(...) return love.graphics.newQuad(...) end)
    scenery.shootingRangeAssets={weaponViews=shootingRangeWeaponViews}
    prepareLazyImages(scenery.shootingRangeAssets)
    for name,file in pairs({background="range-background.png",longRangeBackground="range-long-background.png",targets="target-atlas.png",
        sectionedTarget="sectioned-paper-target.png",sectionedFrame="sectioned-paper-target-frame.png",
        impacts="impact-atlas.png",dirtImpacts="dirt-impact-atlas.png",entrance="range-trail-flag-atlas.png"}) do
        registerRequiredLazyImage(scenery.shootingRangeAssets,name,"assets/sprites/props/shooting-range/"..file)
    end
    local caravanRoot="assets/sprites/caravans/rookery/"
    local caravanCampfirePath=caravanRoot.."animations/campfire-idle-4-v1.png"
    local caravanStallPath=caravanRoot.."animations/merchant-stall-breeze-4-v1.png"
    local caravanPaths={background="assets/backgrounds/crow-caravan-campsite-v1.png",
        wagonBody=caravanRoot.."wagon-body-v1.png",wagonWheel=caravanRoot.."wagon-wheel-v1.png",
        stallBody=caravanRoot.."merchant-stall-body-v2.png",patchedTent=caravanRoot.."patched-tent-v1.png",
        cargoCluster=caravanRoot.."cargo-cluster-v1.png",crowBanner=caravanRoot.."crow-banner-v1.png"}
    for _,path in pairs(caravanPaths) do
        if not love.filesystem.getInfo(path) then missingRequired[#missingRequired+1]=path end
    end
    for _,path in ipairs({caravanCampfirePath,caravanStallPath}) do
        if not love.filesystem.getInfo(path) then missingRequired[#missingRequired+1]=path end
    end
    local caravanAliases={wheel="wagonWheel",tent="patchedTent",cargo="cargoCluster"}
    local caravanAssets={}
    function caravanAssets:release()
        for name in pairs(caravanPaths) do
            local image=rawget(self,name)
            if image and image.release then pcall(image.release,image) end
            rawset(self,name,nil)
        end
        for _,name in ipairs({"campfire","stallBreeze"}) do
            local atlas=rawget(self,name)
            if atlas and atlas.image and atlas.image.release then pcall(atlas.image.release,atlas.image) end
            rawset(self,name,nil)
        end
    end
    scenery.crowCaravanAssets=setmetatable(caravanAssets, {__index=function(assets,name)
        local alias=caravanAliases[name]
        if alias then return assets[alias] end
        local value
        if name=="campfire" then value=loadHorizontalAtlas(caravanCampfirePath,4,"required")
        elseif name=="stallBreeze" then
            local image=requireImage(caravanStallPath)
            value=image and CrowCaravanArt.stallAtlas(image,love.graphics.newQuad)
        elseif caravanPaths[name] then value=requireImage(caravanPaths[name]) end
        if value then rawset(assets,name,value) end
        return value
    end})
    if love.filesystem.getInfo("assets/sprites/NPCS/families") then
        for _,file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/NPCS/families"))do
            if file:match("%.png$")then registerLazyImage(targets.familyImages,file:gsub("%.png$",""),"assets/sprites/NPCS/families/"..file,"family character")end
        end
    end
    table.sort(mobFiles)

    ui.propImages = {}; prepareLazyImages(ui.propImages)
    for _, path in ipairs({"assets/sprites/props", "assets/sprites/items", "assets/sprites/furniture", "assets/sprites/weapons", "assets/sprites/weapon-parts", "assets/sprites/train-decorations", "assets/sprites/ammo", "assets/sprites/gear"}) do
        if love.filesystem.getInfo(path) then for _,file in ipairs(love.filesystem.getDirectoryItems(path)) do if file:match("%.png$") then registerLazyImage(ui.propImages,file:gsub("%.png$", ""),path.."/"..file,"item/furniture/weapon") end end end
    end
    for name,part in pairs(Catalog.repairParts or {}) do
        if type(part.sprite)=="string" then
            if not love.filesystem.getInfo(part.sprite) then AssetDiagnostics.record(part.sprite,"weapon repair component","dedicated sprite is missing") end
            registerLazyImage(ui.propImages,name,part.sprite,"weapon repair component")
        end
    end
    for alias,target in pairs(Catalog.repairPartAliases or {}) do
        local part=rawget(Catalog.repairParts or {},target)
        if part and type(part.sprite)=="string" then registerLazyImage(ui.propImages,alias,part.sprite,"weapon repair component") end
    end
    local itemAnimations=LazyGroups.new(targets.itemIdleImages)
    residentGroups[scenery].items=itemAnimations
    itemAnimations:add("flower-pot","world",function()return {ui.propImages["flower-pot"],loadImage("assets/sprites/items/animations/flower-pot-idle-2.png"),loadImage("assets/sprites/items/animations/flower-pot-idle-3.png")}end)

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
    sceneAssets:add("worldTrainSmokeFrames","train",function()
        local frames={}
        for index = 1, 3 do
            local image = loadImage("assets/sprites/train/animations/locomotive-red-run-" .. index .. ".png","train scenery")
            if image then
                local imageWidth,imageHeight=image:getDimensions()
                frames[index]={image=image,
                    quad=love.graphics.newQuad(0,0,imageWidth,math.min(225,imageHeight),imageWidth,imageHeight)}
            end
        end
        return frames
    end)
    sceneImage("redTrain","assets/sprites/train/locomotive-red.png","trainMarker","train scenery")
    sceneAssets:add("worldTrain","train",function()return scenery.redTrain end)
    scenery.generatedAlphaCutoffShader = loadAlphaCutoffShader()
    sceneImage("worldTrainBody","assets/sprites/train/animations/locomotive-red-body-v2.png","train","train scenery")
    sceneAssets:add("worldTrainRunningGear","train",function()
        local runningGearImage=loadImage(
            "assets/sprites/train/animations/locomotive-running-gear-components-v1.png","train scenery")
        if runningGearImage then
            local gearWidth,gearHeight=runningGearImage:getDimensions()
            local function component(x,y,w,h,originX,originY,length)
                return {quad=love.graphics.newQuad(x,y,w,h,gearWidth,gearHeight),
                    originX=originX,originY=originY,length=length}
            end
            return {image=runningGearImage,
                largeWheel=component(130,40,560,560,282,281),
                smallWheel=component(950,160,380,380,192,193),
                couplingRod=component(130,690,520,170,65,87,378),
                connectingRod=component(790,650,720,210,634,116,558),
                jointPin=component(1070,830,170,140,82,67)}
        end
    end)
    scenery.trainCarImages = {}
    local trainCars=LazyGroups.new(scenery.trainCarImages)
    residentGroups[scenery].cars=trainCars
    for _, entry in ipairs(Catalog.trainCarCatalog) do
        local id=entry.id
        trainCars:add(id,id,function()return loadImage("assets/sprites/train/cars/"..id..".png","train scenery")end)
    end
    trainCars:add("living-car","living-car",function()return loadImage("assets/sprites/train/cars/living-car.png","train scenery")end)
    sceneAssets:add("trainCarBogie","train",function()return loadHorizontalAtlas("assets/sprites/train/animations/train-car-bogie-run-4-v1.png",4,"train scenery")end)
    sceneImage("track","assets/sprites/tracks/railway-track-v2.png","train","train scenery")
    sceneAssets:add("ballastPocketFrames","train",function()return loadVerticalAtlas("assets/sprites/tracks/railway-ballast-pocket-run-4-v1.png",4,"train scenery")end)

    sceneAssets:add("projectiles","battle",function()
        local projectileImage = loadImage("assets/sprites/projectiles/projectiles-packed-v1.png","battle scenery")
        if projectileImage then
            local imageWidth, imageHeight = projectileImage:getDimensions()
            local cellWidth = imageWidth / 5
            local atlas = {image = projectileImage, w = cellWidth, h = imageHeight, quads = {}}
            for index = 1, 5 do atlas.quads[index] = love.graphics.newQuad((index - 1) * cellWidth, 0, cellWidth, imageHeight, imageWidth, imageHeight) end
            return atlas
        end
    end)

    sceneAssets:add("stopGround","stop",function()
        local groundImage = loadImage("assets/sprites/ground/stop-ground-textures-v1.png","scenery")
        if groundImage then
            local imageWidth, imageHeight = groundImage:getDimensions()
            local atlas = {image = groundImage, w = imageWidth / 2, h = imageHeight / 2, quads = {}}
            for index = 1, 4 do
                local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
                atlas.quads[index] = love.graphics.newQuad(column * imageWidth / 2, row * imageHeight / 2, imageWidth / 2, imageHeight / 2, imageWidth, imageHeight)
            end
            return atlas
        end
    end)

    local battleFiles={{"WASTELAND", "wasteland-tiles-v2.png", "wasteland-tiles-v3.png", "wasteland-tiles-v4.png"},
        {"FOREST", "forest-tiles-v1.png", "forest-tiles-v2.png", "forest-tiles-v3.png"},
        {"TOWN RUINS", "town-ruins-tiles-v1.png", "town-ruins-tiles-v2.png", "town-ruins-tiles-v3.png"},
        {"MOUNTAINS", "mountain-tiles-v1.png", "mountain-tiles-v2.png", "mountain-tiles-v3.png"}}
    scenery.battleAtlases=streamBattleAtlases(battleFiles,function(entry) return loadBattleAtlas(entry[2],entry[1]) end)
    scenery.battleVariations=streamBattleAtlases(battleFiles,function(entry) return loadBattleAtlas(entry[3],entry[1]) end)
    scenery.battleAccents=streamBattleAtlases(battleFiles,function(entry)
        local atlas=loadGeneratedBattleAtlas(entry[4]); if atlas then atlas.name=entry[1] end
        return atlas
    end)
    sceneAssets:add("battleObstacles","battle",function()return loadGeneratedBattleAtlas("battle-obstacles-v1.png")end)

    -- Settlement sprites now provide the complete stop surface and buildings.
    -- Keep only chicken assets from the wildlife module for future dynamic spawns.
    scenery.stopWildlife, scenery.stopWildlifeFeeding = {}, {}
    local wildlife=LazyGroups.new(scenery.stopWildlife)
    local feeding=LazyGroups.new(scenery.stopWildlifeFeeding)
    residentGroups[scenery].wildlife=wildlife;residentGroups[scenery].feeding=feeding
    for _,file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/stop-wildlife"))do
        if file:match("%.png$") and not file:find("atlas")then
            local name=file:gsub("%.png$","");local path="assets/sprites/stop-wildlife/"..file
            wildlife:add(name,"stop",function()return loadImage(path,"wildlife")end)
        end
    end
    for _,file in ipairs({"chicken-rooster-walk.png","chicken-hen-walk.png","chicken-chick-walk.png"})do
        local key=file
        wildlife:add(key,"stop",function()return loadImage("assets/sprites/stop-wildlife/chickens/"..key,"wildlife")end)
    end
    wildlife:add("field-mouse-walk.png","stop",function()return scenery.stopWildlife["field-mouse-walk"]end)
    scenery.eventArt = EventUI.load(function(path) return loadImage(path,"event UI") end)
    if love.filesystem.getInfo("assets/sprites/stop-wildlife/animations") then
        for _, file in ipairs(love.filesystem.getDirectoryItems("assets/sprites/stop-wildlife/animations")) do
            local name = file:match("^(.-)%-feed%.png$")
            if name then
                local key,path=name,"assets/sprites/stop-wildlife/animations/"..file
                feeding:add(key,"stop",function()return loadImage(path,"wildlife")end)
            end
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
function Assets.releaseIntroImages(scenery,runtime)
    local keep
    if runtime and runtime.state=="slots" then
        local TitleSnapshots=require("game.title_snapshots")
        keep={titleImage=true,titleHeaderBackdrop=true,titleFooterBackdrop=true}
        for side=0,1 do
            keep["titleSnapshot_"..TitleSnapshots.playback(runtime.animationClock or 0,side).id]=true
        end
    end
    releaseLazyImages(scenery,keep)
end

local function retainSceneGroups(scenery,runtime,options)
    local groups=residentGroups[scenery];if not groups then return end
    options=options or {}
    local data=runtime.saveData
    if runtime.state=="slots" or runtime.state=="intro" then releaseItemAtlases(residentTargets[scenery].ui)end
    local battle=runtime.state=="battle" or runtime.battle~=nil or options.battle
    local hidden=options.shootingRange or runtime.shootingRange~=nil or runtime.scene=="lastStand"
        or LastStandLife.active(data)~=nil or data and data.trainAmbush and data.trainAmbush.active==true
    local world=data~=nil and (runtime.state=="game" or runtime.state=="event") and not battle and not hidden
    local train=world and runtime.scene=="train"
    local stop=world and runtime.scene=="stop"
    local keep={train=train,trainMarker=train or stop,home=world and (train or runtime.scene=="house"),
        stop=stop,battle=battle,world=world}
    groups.scene:retain(keep)
    groups.wildlife:retain(keep);groups.feeding:retain(keep)
    groups.items:retain(keep,residentTargets[scenery].ui.propImages)
    local cars={}
    if train then for _,id in ipairs(data.trainCars or {})do cars[id]=true end end
    groups.cars:retain(cars)
end

-- Called before settlement/animation preparation, without decoding any images.
function Assets.retainResidentArt(scenery,runtime,portraits,npcActor)
    retainSceneGroups(scenery,runtime)
    local targets=residentTargets[scenery];if not targets then return end
    if runtime.state~="characters" then releaseLazyImages(targets.characterImages,portraits or {})end
    local family={}
    if runtime.saveData and (runtime.scene=="stop" or runtime.scene=="house") and not runtime.battle then
        for _,member in ipairs(npcActor and npcActor.family or {})do
            for _,pose in ipairs({"walk","lay","idle"})do
                for frame=1,2 do family[member.kind.."-"..pose.."-"..frame]=true end
            end
        end
    end
    releaseLazyImages(targets.familyImages,family)
end

function Assets.releaseDormantSceneArt(scenery,runtime,keep)
    if not scenery or not runtime then return end
    keep=keep or {}
    retainSceneGroups(scenery,runtime,keep)
    if runtime.state~="battle" and not keep.battle then
        if scenery.battleAtlases then scenery.battleAtlases:release() end
        if scenery.battleVariations then scenery.battleVariations:release() end
        if scenery.battleAccents then scenery.battleAccents:release() end
    end
    if runtime.state~="event" and not keep.event and scenery.eventArt and scenery.eventArt.release then
        scenery.eventArt:release()
    end
    if not runtime.firstAid and not keep.firstAid and scenery.firstAidAssets then
        releaseLazyImages(scenery.firstAidAssets)
        releaseLazyImages(scenery.firstAidAssets.bandageStrips)
    end
    if not runtime.shootingRange and not keep.shootingRange and scenery.shootingRangeAssets then
        local keepEntrance=runtime.state=="game" and runtime.scene=="stop"
        releaseLazyImages(scenery.shootingRangeAssets,keepEntrance and {entrance=true} or nil)
        if scenery.shootingRangeAssets.weaponViews then scenery.shootingRangeAssets.weaponViews:release() end
    end
    if (runtime.state~="game" or runtime.scene~="caravan") and not keep.caravan and scenery.crowCaravanAssets
        and scenery.crowCaravanAssets.release then
        scenery.crowCaravanAssets:release()
    end
end

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
