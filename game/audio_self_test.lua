local AudioSelfTest = {}

local function sourceFor(path,kind,created)
    local source={path=path,kind=kind,playing=false,released=false,releaseCount=0,playCount=0}
    function source:setVolume(value) self.volume=value end
    function source:setLooping(value) self.looping=value end
    function source:play() assert(not self.released,"released source played"); self.playing=true; self.playCount=self.playCount+1 end
    function source:pause() self.playing=false end
    function source:stop() self.playing=false end
    function source:release() self.released=true; self.releaseCount=self.releaseCount+1 end
    function source:isPlaying() assert(not self.released,"released source queried"); return self.playing end
    function source:seek(value) self.position=value end
    function source:tell() return self.position or 0 end
    function source:clone() return sourceFor(self.path,self.kind,created) end
    created[#created+1]=source
    return source
end

function AudioSelfTest.run(Audio,Catalog)
    local directories={}
    local files={}
    for _,category in ipairs(Catalog.musicCategories) do directories["sounds/music/"..category]={} end
    directories["sounds/music/train"]={"alpha.wav","bad.wav","beta.wav"}
    directories["sounds/soundEffects/rain"]={"Rainlit Shelter.mp3","steady-rain.wav"}
    for _,kind in ipairs(Catalog.sfxCategories) do directories["sounds/soundEffects/"..kind]={} end
    for _,path in ipairs({"sounds/soundEffects/train/trainArrive","sounds/soundEffects/train/traindepart","sounds/soundEffects/train/trainDoor"}) do directories[path]={} end
    for directory,names in pairs(directories) do for _,name in ipairs(names) do files[directory.."/"..name]=true end end
    local filesystem={}
    function filesystem.getInfo(path)
        if directories[path] then return {type="directory"} end
        if files[path] then return {type="file"} end
        return nil
    end
    function filesystem.getDirectoryItems(path) return directories[path] or {} end

    local created={}
    local audioApi={}
    function audioApi.newSource(path,kind)
        if path:find("bad.wav",1,true) then error("fixture decode failure") end
        return sourceFor(path,kind,created)
    end
    local engine=Audio.new({filesystem=filesystem,audio=audioApi,random=function() return 1 end,catalog=Catalog})
    local settings={station="8bit",musicVolume=.1,sfxVolume=.5,rainVolume=.2,rainEnabled=true,musicPaused=false,musicMuted=false}

    assert(#engine.musicFiles.train==3,"audio audit expected three train fixtures")
    assert(#engine.rainFiles==1 and engine.rainFiles[1]:find("steady%-rain"),"music leaked into the rain bus")
    engine:update(settings,"train")
    assert(engine.category=="train" and engine.nowPlaying and not engine.nowPlaying:find("bad",1,true),"failed track was not skipped")
    assert(next(engine.failedMusic)~=nil,"failed track was not quarantined")
    local first=engine.music
    first.playing=false
    engine:update(settings,"train")
    assert(first.released and first.releaseCount==1,"replaced music source was not released exactly once")
    assert(engine.music~=first and engine.music:isPlaying(),"playlist did not advance after track completion")
    local second=engine.music
    assert(second.path~=first.path,"shuffle bag repeated a track before exhausting the playlist")
    second.playing=false; engine:update(settings,"train")
    assert(engine.music.path~=second.path,"shuffle bag repeated across its refill boundary")
    assert(engine:effectiveCategory({station="chill"},"train")=="chill","station did not override scene score")
    assert(engine:effectiveCategory({station="chill"},"bossFight")=="bossFight","boss score did not override station")
    engine:suspend(settings)
    assert(engine.suspended and not engine.music:isPlaying() and not engine.rain:isPlaying(),"focus loss did not suspend audio")
    engine:resume(settings)
    assert(not engine.suspended and engine.music:isPlaying() and engine.rain:isPlaying(),"focus gain did not resume audio")
    engine:update(settings,nil)
    assert(engine.music==nil and engine.rain==nil,"title state did not release music and ambience")
    engine:shutdown()
    return {created=#created,failedTrackSkipped=true,replacementReleased=true,shuffleBag=true,priority=true,focus=true,titleSilent=true}
end

return AudioSelfTest
