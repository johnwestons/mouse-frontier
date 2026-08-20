local Settlements=require("game.settlements")
local CharacterAnimation=require("game.character_animation")
local Assets=require("game.assets")
local InteriorStreamer=require("game.interior_streamer")

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

function AssetStreamer:update(state,scene,data,battle,npcActor)
    if not data then
        Settlements.release(self.settlements)
        CharacterAnimation.retain(self.characterAnimations,{})
        Assets.retainAnimationImages(self.legacyAnimationTables,{})
        self.interiors:release()
        self.lastSettlement=nil
        self.lastSignature=""
        return
    end


    if state=="game" and scene=="house" then
        self.interiors:activate(activeInteriorIndex(data))
    else
        self.interiors:release()
    end

    if state=="game" and scene=="stop" then
        local location=data.location or 1
        if self.lastSettlement~=location then Settlements.activate(self.settlements,location); self.lastSettlement=location end
    elseif self.lastSettlement then
        Settlements.release(self.settlements); self.lastSettlement=nil
    end

    local keep={}
    add(keep,data.character)
    if state=="battle" and battle then
        for _,unit in ipairs(battle.units or {}) do add(keep,unit.file) end
    elseif scene=="train" then
        for _,passenger in ipairs(data.passengers or {}) do add(keep,passenger.npc) end
    elseif scene=="stop" or scene=="house" then
        add(keep,data.currentNPC)
        if npcActor and npcActor.family then
            for _,member in ipairs(npcActor.family) do add(keep,member.file or member.npc) end
        end
    end

    local names={}; for file in pairs(keep) do names[#names+1]=file end; table.sort(names)
    local signature=table.concat(names,"|")
    if signature~=self.lastSignature then
        CharacterAnimation.retain(self.characterAnimations,keep)
        Assets.retainAnimationImages(self.legacyAnimationTables,keep)
        self.lastSignature=signature
        collectgarbage("collect")
    end
end

return AssetStreamer
