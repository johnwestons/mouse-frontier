local AudioCatalog = {}

AudioCatalog.musicCategories={"battle","bossFight","chill","vibes","endingHappy","insideHomes","stops","train"}
AudioCatalog.sfxCategories={"bow","doors","gunshot","menu","slash","sword","talking","walkingSteps"}

local validStations={['8bit']=true,chill=true,vibes=true}
local gameplayOverrides={battle=true,bossFight=true,endingHappy=true}
local excludedRain={
    ["rainlit shelter.mp3"]=true, -- This is a complete song, not ambience.
    ["865261__robo9418__rain-hitting-window.wav"]=true, -- Roughly 12 dB quieter than the curated rain set.
}

local function basename(path)
    return (path:match("[^/\\]+$") or path):lower()
end

function AudioCatalog.isValidStation(station)
    return validStations[station]==true
end

function AudioCatalog.normalizeStation(station)
    return AudioCatalog.isValidStation(station) and station or "8bit"
end

function AudioCatalog.stationLabel(station)
    station=AudioCatalog.normalizeStation(station)
    return station=="chill" and "CHILL RADIO" or (station=="vibes" and "VIBES RADIO" or "8-BIT SCORE")
end

function AudioCatalog.resolveCategory(station,gameplayCategory)
    if not gameplayCategory then return nil end
    if gameplayOverrides[gameplayCategory] then return gameplayCategory end
    station=AudioCatalog.normalizeStation(station)
    return (station=="chill" or station=="vibes") and station or gameplayCategory
end

function AudioCatalog.shouldLoopMusic(_category)
    -- Every registered category is a playlist. The update loop advances after a
    -- track ends, including during unusually long battles and ending screens.
    return false
end

function AudioCatalog.normalizedMusicStem(path)
    local stem=basename(path):gsub("%.[^%.]+$","")
    local previous
    repeat
        previous=stem
        stem=stem:gsub("%s*%(1%)$",""):gsub("[12]$","")
    until stem==previous
    return stem
end

function AudioCatalog.canonicalMusicFiles(files)
    local groups={}
    for _,path in ipairs(files or {}) do
        local key=AudioCatalog.normalizedMusicStem(path)
        local group=groups[key] or {}; groups[key]=group; group[#group+1]=path
    end
    local selected={}
    for _,group in pairs(groups) do
        table.sort(group,function(a,b)
            local aName=basename(a):gsub("%.[^%.]+$","")
            local bName=basename(b):gsub("%.[^%.]+$","")
            local aChanged=AudioCatalog.normalizedMusicStem(a)~=aName
            local bChanged=AudioCatalog.normalizedMusicStem(b)~=bName
            if aChanged~=bChanged then return not aChanged end
            if #aName~=#bName then return #aName<#bName end
            return a:lower()<b:lower()
        end)
        selected[#selected+1]=group[1]
    end
    table.sort(selected)
    return selected
end

function AudioCatalog.includeRain(path)
    return not excludedRain[basename(path)]
end

return AudioCatalog
