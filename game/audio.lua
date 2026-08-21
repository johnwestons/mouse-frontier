local Audio = {}
Audio.__index = Audio

local function filesIn(path)
    local files = {}
    if not love.filesystem.getInfo(path) then return files end
    for _, name in ipairs(love.filesystem.getDirectoryItems(path)) do
        local full = path .. "/" .. name
        local info = love.filesystem.getInfo(full)
        local extension=name:lower():match("%.([^%.]+)$")
        if info and info.type == "file" and (extension=="wav" or extension=="mp3" or extension=="ogg" or extension=="flac") then
            files[#files + 1] = full
        end
    end
    table.sort(files)
    return files
end

local function report(self, message)
    self.lastError = message
    print("[AUDIO] " .. message)
end

local function loadSource(self, path, kind)
    local ok, source = pcall(love.audio.newSource, path, kind)
    if not ok then report(self, "Could not load " .. path .. ": " .. tostring(source)); return nil end
    return source
end

function Audio.new()
    local self = setmetatable({musicFiles = {}, sfx = {}, music = nil, rain = nil, arrivalSource = nil, category = nil, lastError = nil, nowPlaying = nil, history = {}, historyPosition = {}, sfxCache = {}, activeSfx = {}}, Audio)
    for _, category in ipairs({"battle", "bossFight", "chill", "vibes", "endingHappy", "insideHomes", "stops", "train"}) do
        self.musicFiles[category] = filesIn("sounds/music/" .. category)
        print("[AUDIO] Registered "..#self.musicFiles[category].." track(s) for "..category)
    end
    for _, kind in ipairs({"bow", "doors", "gunshot", "hurtMale", "hurtMob", "menu", "nature", "rain", "slash", "sword", "talking", "walkingSteps"}) do
        self.sfx[kind] = filesIn("sounds/soundEffects/" .. kind)
    end
    self.sfx.trainArrive = filesIn("sounds/soundEffects/train/trainArrive")
    self.sfx.trainDepart = filesIn("sounds/soundEffects/train/traindepart")
    self.sfx.trainDoor = filesIn("sounds/soundEffects/train/trainDoor")
    self.sfx.trainTravel = filesIn("sounds/soundEffects/train/trainTraveling")
    self.rainFiles = filesIn("sounds/soundEffects/rain")
    return self
end

function Audio:musicVolume(settings)
    return settings.musicMuted and 0 or (settings.musicVolume or .10)
end

function Audio:rainVolume(settings)
    return settings.musicMuted and 0 or (settings.rainVolume or .20)
end

function Audio:playMusicPath(path,category,settings)
    if self.music then self.music:stop() end
    local source=loadSource(self,path,"stream")
    if not source then return false end
    local continuousStation=settings.station=="chill" or settings.station=="vibes"
    source:setVolume(self:musicVolume(settings)); source:setLooping(not continuousStation)
    self.music,self.category,self.nowPlaying=source,category,path; self.lastError=nil
    if not settings.musicPaused then source:play() end
    return true
end

function Audio:rememberTrack(category,path)
    local history=self.history[category] or {}; self.history[category]=history
    local position=self.historyPosition[category] or #history
    while #history>position do table.remove(history) end
    history[#history+1]=path; self.historyPosition[category]=#history
end

function Audio:chooseNext(category)
    local pool=self.musicFiles[category] or {}; if #pool==0 then return nil end
    if #pool==1 then return pool[1] end
    local path
    repeat path=pool[love.math.random(#pool)] until path~=self.nowPlaying
    return path
end

function Audio:nextTrack(settings,category)
    category=(settings.station=="chill" or settings.station=="vibes") and settings.station or category
    local history=self.history[category] or {}; local position=self.historyPosition[category] or #history
    local path
    if position<#history then position=position+1; path=history[position]; self.historyPosition[category]=position
    else path=self:chooseNext(category); if path then self:rememberTrack(category,path) end end
    if path then settings.musicPaused=false; return self:playMusicPath(path,category,settings) end
    report(self,"No music registered for category "..tostring(category)); return false
end

function Audio:previousTrack(settings,category)
    category=(settings.station=="chill" or settings.station=="vibes") and settings.station or category
    local history=self.history[category] or {}; local position=self.historyPosition[category] or #history
    if position>1 then position=position-1; self.historyPosition[category]=position; settings.musicPaused=false; return self:playMusicPath(history[position],category,settings) end
    if self.music then self.music:seek(0); if settings.musicPaused then settings.musicPaused=false; self.music:play() end; return true end
    return self:nextTrack(settings,category)
end

function Audio:togglePause(settings)
    settings.musicPaused=not settings.musicPaused
    if self.music then if settings.musicPaused then self.music:pause() else self.music:play() end end
    return settings.musicPaused
end

function Audio:toggleMute(settings)
    settings.musicMuted=not settings.musicMuted
    if self.music then self.music:setVolume(self:musicVolume(settings)) end
    if self.rain then self.rain:setVolume(self:rainVolume(settings)) end
    return settings.musicMuted
end

function Audio:installGunPools()
    self.sfx.gunshotLight={
        "sounds/soundEffects/gunshot/385811__morganpurkis__single-pistol-gunshot-3.wav","sounds/soundEffects/gunshot/391328__morganpurkis__single-pistol-gunshot-4.wav",
        "sounds/soundEffects/gunshot/391846__morganpurkis__single-pistol-gunshot-42.wav","sounds/soundEffects/gunshot/392229__morganpurkis__single-pistol-gunshot-33.wav",
        "sounds/soundEffects/gunshot/427594__michorvath__22-magnum-pistol-shot.wav","sounds/soundEffects/gunshot/718174__tb0y298__pistol-shot-1.wav","sounds/soundEffects/gunshot/718965__tb0y298__pistol-shot-2.wav"}
    self.sfx.gunshotMedium={"sounds/soundEffects/gunshot/147901__tcawte__gunshot.mp3","sounds/soundEffects/gunshot/171236__alukahn__gunshot2.wav","sounds/soundEffects/gunshot/569174__coolabc__makarov-shoot.wav","sounds/soundEffects/gunshot/773867__mrgungus__gunshot-4.wav"}
    self.sfx.gunshotHeavy={"sounds/soundEffects/gunshot/427598__michorvath__ar15-pistol-shot.wav","sounds/soundEffects/gunshot/615028__zreimbach__designed-gunshot.wav"}
end

function Audio:playSfx(kind, settings, battle)
    local pool = self.sfx[kind]
    if not pool or #pool == 0 then report(self, "No sound files registered for " .. tostring(kind)); return nil end
    local path = battle and battle.soundChoices and battle.soundChoices[kind] or pool[love.math.random(#pool)]
    if battle then battle.soundChoices = battle.soundChoices or {}; battle.soundChoices[kind] = path end
    local prototype=self.sfxCache[path]
    if not prototype then prototype=loadSource(self,path,"static"); if prototype then self.sfxCache[path]=prototype end end
    local source
    if prototype then
        local ok,clone=pcall(prototype.clone,prototype)
        source=ok and clone or loadSource(self,path,"static")
    end
    if source then
        source:setVolume(settings.sfxVolume)
        if kind=="trainArrive" then
            -- The useful arrival cue is the stopping section of the recording.
            -- Start at 13s and let update() terminate it at 21s.
            source:seek(13)
            source:setLooping(false)
            self.arrivalSource=source
        end
        source:play(); self.activeSfx[#self.activeSfx+1]=source; return source
    end
    return nil
end

function Audio:update(settings, category)
    for index=#self.activeSfx,1,-1 do
        local source=self.activeSfx[index]
        if not source:isPlaying() then if source.release then pcall(source.release,source) end; table.remove(self.activeSfx,index) end
    end
    if self.arrivalSource and self.arrivalSource:isPlaying() and self.arrivalSource:tell() >= 21 then
        self.arrivalSource:stop(); self.arrivalSource=nil
    elseif self.arrivalSource and not self.arrivalSource:isPlaying() then
        self.arrivalSource=nil
    end
    local chill = settings.station == "chill"
    local continuousStation = chill or settings.station == "vibes"
    category = continuousStation and settings.station or category
    if not (self.music and self.category == category and (self.music:isPlaying() or settings.musicPaused)) then
        local pool = self.musicFiles[category] or {}
        if #pool == 0 then report(self, "No music registered for category " .. tostring(category)); self.music = nil
        else
            local path=self:chooseNext(category); self:rememberTrack(category,path); self:playMusicPath(path,category,settings)
        end
    elseif self.music then self.music:setVolume(self:musicVolume(settings)); if settings.musicPaused and self.music:isPlaying() then self.music:pause() end end
    local wantsRain = settings.rainEnabled
    if wantsRain and not (self.rain and self.rain:isPlaying()) then
        if #self.rainFiles > 0 then local source=loadSource(self,self.rainFiles[love.math.random(#self.rainFiles)],"stream"); if source then source:setLooping(true); source:setVolume(self:rainVolume(settings)); source:play(); self.rain=source end end
    elseif wantsRain and self.rain then self.rain:setVolume(self:rainVolume(settings))
    elseif self.rain then self.rain:stop(); self.rain=nil end
end

function Audio:resetMusic()
    if self.music then self.music:stop() end
    self.music, self.category, self.nowPlaying = nil, nil, nil
end

function Audio:shutdown()
    if self.music then self.music:stop(); if self.music.release then pcall(self.music.release,self.music) end end
    if self.rain then self.rain:stop(); if self.rain.release then pcall(self.rain.release,self.rain) end end
    for _,source in ipairs(self.activeSfx or {}) do source:stop(); if source.release then pcall(source.release,source) end end
    for _,source in pairs(self.sfxCache or {}) do source:stop(); if source.release then pcall(source.release,source) end end
    self.music,self.rain,self.arrivalSource=nil,nil,nil; self.activeSfx={}; self.sfxCache={}
end

return Audio
