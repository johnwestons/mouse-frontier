local DefaultCatalog = require("game.audio_catalog")

local Audio = {}
Audio.__index = Audio

local function safeCall(source,method,...)
    if not source or type(source[method])~="function" then return false end
    return pcall(source[method],source,...)
end

local function stopAndRelease(source)
    if not source then return end
    safeCall(source,"stop")
    safeCall(source,"release")
end

local function filesIn(filesystem,path)
    local files={}
    if not filesystem.getInfo(path) then return files end
    for _,name in ipairs(filesystem.getDirectoryItems(path)) do
        local full=path.."/"..name
        local info=filesystem.getInfo(full)
        local extension=name:lower():match("%.([^%.]+)$")
        if info and info.type=="file" and (extension=="wav" or extension=="mp3" or extension=="ogg" or extension=="flac") then
            files[#files+1]=full
        end
    end
    table.sort(files)
    return files
end

local function report(self,message)
    if self.lastError==message then return end
    self.lastError=message
    print("[AUDIO] "..message)
end

local function packagedAudioPath(self,path)
    if self.filesystem.getInfo(path) then return path end
    local stem=path:gsub("%.[^./]+$","")
    for _,extension in ipairs({".ogg",".mp3",".wav",".flac"}) do
        local candidate=stem..extension
        if self.filesystem.getInfo(candidate) then return candidate end
    end
    return path
end

local function loadSource(self,path,kind)
    path=packagedAudioPath(self,path)
    local ok,source=pcall(self.audioApi.newSource,path,kind)
    if not ok then report(self,"Could not load "..path..": "..tostring(source)); return nil end
    return source
end

function Audio.new(dependencies)
    dependencies=dependencies or {}
    local filesystem=dependencies.filesystem or (love and love.filesystem)
    local audioApi=dependencies.audio or (love and love.audio)
    local random=dependencies.random or (love and love.math and love.math.random) or math.random
    assert(filesystem and audioApi,"audio requires filesystem and audio backends")
    local catalog=dependencies.catalog or DefaultCatalog
    local self=setmetatable({
        filesystem=filesystem,audioApi=audioApi,random=random,catalog=catalog,
        musicFiles={},sfx={},music=nil,rain=nil,rainPath=nil,arrivalSource=nil,category=nil,
        lastError=nil,nowPlaying=nil,history={},historyPosition={},shuffleBags={},rainFiles={},
        failedMusic={},failedRain={},unavailableCategories={},rainUnavailable=false,
        sfxCache={},activeSfx={},suspended=false,resumeMusic=false,resumeRain=false,
    },Audio)
    for _,category in ipairs(catalog.musicCategories) do
        self.musicFiles[category]=catalog.canonicalMusicFiles(filesIn(filesystem,"sounds/music/"..category))
        print("[AUDIO] Registered "..#self.musicFiles[category].." canonical track(s) for "..category)
    end
    for _,kind in ipairs(catalog.sfxCategories) do self.sfx[kind]=filesIn(filesystem,"sounds/soundEffects/"..kind) end
    self.sfx.trainArrive=filesIn(filesystem,"sounds/soundEffects/train/trainArrive")
    self.sfx.trainDepart=filesIn(filesystem,"sounds/soundEffects/train/traindepart")
    self.sfx.trainDoor=filesIn(filesystem,"sounds/soundEffects/train/trainDoor")
    for _,path in ipairs(filesIn(filesystem,"sounds/soundEffects/rain")) do
        if catalog.includeRain(path) then self.rainFiles[#self.rainFiles+1]=path end
    end
    return self
end

function Audio:musicVolume(settings)
    return settings.musicMuted and 0 or (settings.musicVolume or .10)
end

function Audio:rainVolume(settings)
    return settings.rainVolume or .20
end

function Audio:effectiveCategory(settings,category)
    return self.catalog.resolveCategory(settings.station,category)
end

function Audio:refillShuffleBag(category)
    local bag={}
    for _,path in ipairs(self.musicFiles[category] or {}) do
        if not self.failedMusic[path] then bag[#bag+1]=path end
    end
    for index=#bag,2,-1 do
        local other=self.random(index)
        bag[index],bag[other]=bag[other],bag[index]
    end
    if #bag>1 and bag[1]==self.nowPlaying then bag[1],bag[2]=bag[2],bag[1] end
    self.shuffleBags[category]=bag
    return bag
end

function Audio:chooseNext(category)
    local bag=self.shuffleBags[category]
    if not bag or #bag==0 then bag=self:refillShuffleBag(category) end
    if #bag==0 then return nil end
    return table.remove(bag,1)
end

function Audio:playMusicPath(path,category,settings)
    local source=loadSource(self,path,"stream")
    if not source then self.failedMusic[path]=true; return false end
    local ok,message=pcall(function()
        source:setVolume(self:musicVolume(settings))
        source:setLooping(self.catalog.shouldLoopMusic(category))
        if not settings.musicPaused and not self.suspended then source:play() end
    end)
    if not ok then
        stopAndRelease(source); self.failedMusic[path]=true
        report(self,"Could not configure "..path..": "..tostring(message)); return false
    end
    local previous=self.music
    self.music,self.category,self.nowPlaying=source,category,path
    self.unavailableCategories[category]=nil; self.lastError=nil
    if previous and previous~=source then stopAndRelease(previous) end
    return true
end

function Audio:rememberTrack(category,path)
    local history=self.history[category] or {}; self.history[category]=history
    local position=self.historyPosition[category] or #history
    while #history>position do table.remove(history) end
    history[#history+1]=path
    if #history>50 then table.remove(history,1) end
    self.historyPosition[category]=#history
end

function Audio:playNextAvailable(settings,category,remember)
    local pool=self.musicFiles[category] or {}
    for _=1,#pool do
        local path=self:chooseNext(category)
        if not path then break end
        if self:playMusicPath(path,category,settings) then
            if remember~=false then self:rememberTrack(category,path) end
            return true
        end
    end
    self.unavailableCategories[category]=true
    report(self,"No playable music registered for category "..tostring(category))
    if self.category~=category then
        stopAndRelease(self.music); self.music,self.category,self.nowPlaying=nil,nil,nil
    end
    return false
end

function Audio:nextTrack(settings,category)
    category=self:effectiveCategory(settings,category)
    if not category then return false end
    self.unavailableCategories[category]=nil
    local history=self.history[category] or {}
    local position=self.historyPosition[category] or #history
    if position<#history then
        local nextPosition=position+1
        if self:playMusicPath(history[nextPosition],category,settings) then
            self.historyPosition[category]=nextPosition; settings.musicPaused=false; return true
        end
    end
    local played=self:playNextAvailable(settings,category,true)
    if played then settings.musicPaused=false end
    return played
end

function Audio:previousTrack(settings,category)
    category=self:effectiveCategory(settings,category)
    if not category then return false end
    local history=self.history[category] or {}
    local position=self.historyPosition[category] or #history
    if position>1 and self:playMusicPath(history[position-1],category,settings) then
        self.historyPosition[category]=position-1; settings.musicPaused=false; return true
    end
    if self.music and self.category==category then
        safeCall(self.music,"seek",0)
        if settings.musicPaused then settings.musicPaused=false; safeCall(self.music,"play") end
        return true
    end
    return self:nextTrack(settings,category)
end

function Audio:togglePause(settings)
    settings.musicPaused=not settings.musicPaused
    if self.music then
        if settings.musicPaused then safeCall(self.music,"pause") elseif not self.suspended then safeCall(self.music,"play") end
    end
    return settings.musicPaused
end

function Audio:toggleMute(settings)
    settings.musicMuted=not settings.musicMuted
    if self.music then safeCall(self.music,"setVolume",self:musicVolume(settings)) end
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

function Audio:playSfxPath(path,settings,options)
    if self.suspended or not path then return nil end
    local prototype=self.sfxCache[path]
    if not prototype then prototype=loadSource(self,path,"static"); if prototype then self.sfxCache[path]=prototype end end
    local source
    if prototype then
        local ok,clone=pcall(prototype.clone,prototype)
        source=ok and clone or loadSource(self,path,"static")
    end
    if not source then return nil end
    options=options or {}
    source:setVolume((settings.sfxVolume or .55)*(options.volume or 1))
    if options.pitch then safeCall(source,"setPitch",options.pitch) end
    if options.seek then safeCall(source,"seek",options.seek) end
    if options.looping~=nil then safeCall(source,"setLooping",options.looping) end
    source:play(); self.activeSfx[#self.activeSfx+1]=source
    return source
end

function Audio:playSfx(kind,settings,battle)
    if self.suspended then return nil end
    local pool=self.sfx[kind]
    if not pool or #pool==0 then report(self,"No sound files registered for "..tostring(kind)); return nil end
    local path=battle and battle.soundChoices and battle.soundChoices[kind] or pool[self.random(#pool)]
    if battle then battle.soundChoices=battle.soundChoices or {}; battle.soundChoices[kind]=path end
    local options=kind=="trainArrive" and {seek=13,looping=false} or nil
    local source=self:playSfxPath(path,settings,options)
    if kind=="trainArrive" then self.arrivalSource=source end
    return source
end

function Audio:cleanupSfx(stopAll)
    for index=#self.activeSfx,1,-1 do
        local source=self.activeSfx[index]
        if stopAll or not source:isPlaying() then
            if source==self.arrivalSource then self.arrivalSource=nil end
            stopAndRelease(source); table.remove(self.activeSfx,index)
        end
    end
end

function Audio:startRain(settings)
    if self.rainUnavailable or #self.rainFiles==0 then return false end
    local first=self.random(#self.rainFiles)
    for offset=0,#self.rainFiles-1 do
        local path=self.rainFiles[((first+offset-1)%#self.rainFiles)+1]
        if not self.failedRain[path] then
            local source=loadSource(self,path,"stream")
            if source then
                local ok=pcall(function()
                    source:setLooping(true); source:setVolume(self:rainVolume(settings))
                    if not self.suspended then source:play() end
                end)
                if ok then stopAndRelease(self.rain); self.rain,self.rainPath=source,path; return true end
                stopAndRelease(source)
            end
            self.failedRain[path]=true
        end
    end
    self.rainUnavailable=true; report(self,"No playable rain ambience is available"); return false
end

function Audio:update(settings,category)
    self:cleanupSfx(false)
    if self.arrivalSource and self.arrivalSource:isPlaying() and self.arrivalSource:tell()>=21 then self.arrivalSource:stop(); self.arrivalSource=nil end
    if self.suspended then return end
    category=self:effectiveCategory(settings,category)
    if not category then self:resetMusic(); stopAndRelease(self.rain); self.rain,self.rainPath=nil,nil; return end
    if not (self.music and self.category==category and (self.music:isPlaying() or settings.musicPaused)) then
        if not self.unavailableCategories[category] then self:playNextAvailable(settings,category,true) end
    elseif self.music then
        self.music:setVolume(self:musicVolume(settings))
        if settings.musicPaused and self.music:isPlaying() then self.music:pause() end
    end
    if settings.rainEnabled and not (self.rain and self.rain:isPlaying()) then self:startRain(settings)
    elseif settings.rainEnabled and self.rain then self.rain:setVolume(self:rainVolume(settings))
    elseif self.rain then stopAndRelease(self.rain); self.rain,self.rainPath=nil,nil end
end

function Audio:resetMusic()
    stopAndRelease(self.music)
    self.music,self.category,self.nowPlaying=nil,nil,nil
end

function Audio:suspend(_settings)
    if self.suspended then return true end
    self.suspended=true
    self.resumeMusic=self.music and self.music:isPlaying() or false
    self.resumeRain=self.rain and self.rain:isPlaying() or false
    safeCall(self.music,"pause"); safeCall(self.rain,"pause"); self:cleanupSfx(true)
    return true
end

function Audio:resume(settings)
    if not self.suspended then return true end
    self.suspended=false
    if self.resumeMusic and self.music and not settings.musicPaused then safeCall(self.music,"play") end
    if self.resumeRain and self.rain and settings.rainEnabled then safeCall(self.rain,"play") end
    self.resumeMusic,self.resumeRain=false,false
    return true
end

function Audio:shutdown()
    stopAndRelease(self.music); stopAndRelease(self.rain); self:cleanupSfx(true)
    for _,source in pairs(self.sfxCache) do stopAndRelease(source) end
    self.music,self.rain,self.rainPath,self.arrivalSource=nil,nil,nil,nil
    self.sfxCache={}; self.suspended=false
end

return Audio
