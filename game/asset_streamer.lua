local Settlements=require("game.settlements")
local CharacterAnimation=require("game.character_animation")
local Assets=require("game.assets")
local InteriorStreamer=require("game.interior_streamer")
local Home=require("game.home_stop")
local HomeArt=require("game.home_stop_art")
local HomeFox=require("game.home_stop_fox")
local SceneNPCs=require("game.scene_npcs")

local AssetStreamer={}
AssetStreamer.__index=AssetStreamer

function AssetStreamer.new(options)
    return setmetatable({
        settlements=options.settlements,
        characterAnimations=options.characterAnimations,
        legacyAnimationTables=options.legacyAnimationTables or {},
        interiors=InteriorStreamer.new(options.interiorFiles),
        lastSettlement=nil,
        lastSignature=nil,
        scenery=options.scenery,
    },AssetStreamer)
end

local function activeInteriorIndex(data)
    local layouts=data.stopLayouts
    local layout=layouts and layouts[tostring(data.location or 1)]
    if not layout then return nil end
    local door=data.activeHouseDoor
    local home=door and layout.houseDoors and layout.houseDoors[tostring(door)]
    return (home and home.interior) or layout.interior
end

function AssetStreamer:getInterior(index)
    return self.interiors:get(index)
end

local function add(keep,file)
    if type(file)=="string" and file~="" then keep[file]=true end
end

local function addResidents(keep,data,scene,npcActor)
    local actors=SceneNPCs.hasResidents(data) and SceneNPCs.list(data,scene,data.activeHouseDoor) or {npcActor}
    for _,actor in ipairs(actors) do
        add(keep,actor.file)
        for _,member in ipairs(actor.family or {}) do add(keep,member.file or member.npc) end
    end
end

function AssetStreamer:update(state,scene,data,battle,npcActor,characterPreviewFile,companionCharacter)
    -- Drop the previous scene's images before any new interior, settlement or
    -- actor sheet is uploaded. This also runs on guest replica preparations.
    local home=state=="game" and scene=="stop" and Home.isHome(data)
    if not home then HomeArt.release() end
    local portraits={}
    if data then
        add(portraits,data.character);add(portraits,companionCharacter)
        if home then add(portraits,Home.npc) end
        if state=="ending" then
            add(portraits,(data.npcRoster or {})[1]);add(portraits,(data.npcRoster or {})[2])
        elseif state=="battle" and battle then
            for _,unit in ipairs(battle.units or {})do add(portraits,unit.file)end
        elseif scene=="train" then
            for _,passenger in ipairs(data.passengers or {})do add(portraits,passenger.npc)end
        elseif scene=="stop" or scene=="house" then add(portraits,data.currentNPC); addResidents(portraits,data,scene,npcActor)
        elseif scene=="lastStand" then add(portraits,"otter-scout.png")
        elseif scene=="caravan" then add(portraits,"crow-merchant.png")end
    elseif state=="characters" then add(portraits,characterPreviewFile)end
    if self.scenery then
        local npcActors=data and SceneNPCs.hasResidents(data) and SceneNPCs.list(data,scene,data.activeHouseDoor) or nil
        Assets.retainResidentArt(self.scenery,{state=state,scene=scene,saveData=data,battle=battle},portraits,npcActor,npcActors)
    end
    if not data then
        Settlements.release(self.settlements)
        local keep={}
        if state=="characters" then add(keep,characterPreviewFile) end
        CharacterAnimation.retain(self.characterAnimations,keep)
        Assets.retainAnimationImages(self.legacyAnimationTables,{})
        self.interiors:release()
        self.lastSettlement=nil
        local names={}; for file in pairs(keep) do names[#names+1]=file end; table.sort(names)
        self.lastSignature=table.concat(names,"|")
        return
    end


    if state=="game" and scene=="house" then
        self.interiors:activate(activeInteriorIndex(data))
    else
        self.interiors:release()
    end

    if state=="game" and scene=="stop" and not home then
        local location=data.location or 1
        if self.lastSettlement~=location then Settlements.activate(self.settlements,location); self.lastSettlement=location end
    elseif self.lastSettlement then
        Settlements.release(self.settlements); self.lastSettlement=nil
    end

    local keep={}
    add(keep,data.character)
    if home then
        add(keep,Home.npc)
    else HomeFox.release() end
    add(keep,companionCharacter)
    if state=='ending' then
        add(keep,(data.npcRoster or {})[1]); add(keep,(data.npcRoster or {})[2])
    elseif state=="battle" and battle then
        for _,unit in ipairs(battle.units or {}) do add(keep,unit.file) end
    elseif scene=="train" then
        for _,passenger in ipairs(data.passengers or {}) do add(keep,passenger.npc) end
    elseif scene=="stop" or scene=="house" then
        add(keep,data.currentNPC)
        addResidents(keep,data,scene,npcActor)
        if npcActor and npcActor.family then
            for _,member in ipairs(npcActor.family) do add(keep,member.file or member.npc) end
        end
    elseif scene=="lastStand" then
        add(keep,"otter-scout.png")
    elseif scene=="caravan" then
        add(keep,"crow-merchant.png")
    end

    local names={}; for file in pairs(keep) do names[#names+1]=file end; table.sort(names)
    local signature=table.concat(names,"|")
    if signature~=self.lastSignature then
        CharacterAnimation.retain(self.characterAnimations,keep)
        Assets.retainAnimationImages(self.legacyAnimationTables,keep)
        self.lastSignature=signature
    end
end

return AssetStreamer
