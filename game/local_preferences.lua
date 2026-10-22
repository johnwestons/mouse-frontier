-- Device settings never live on a campaign or a network actor record. Weak
-- bindings expose local presentation without changing serialized game data.
local Accessibility=require("game.accessibility")
local AudioCatalog=require("game.audio_catalog")
local Players=require("game.coop_players")
local Codec=require("game.net.codec")
local Preferences={PATH="local-preferences.txt"}
local Store={}; Store.__index=Store
local bindings=setmetatable({},{__mode="k"})
local AUDIO={musicVolume=.10,sfxVolume=.55,rainVolume=.20,musicMuted=false,musicPaused=false}
local CONNECTION_MODES={auto=true,wifi=true,usb=true}
local LIMITS={maxBytes=8192,maxDepth=5,maxEntries=80,maxStringBytes=128}

local function normalized(value)
    value=type(value)=="table" and value or {}
    local result={version=1,configured=value.configured==true,audio={},accessibility={}}
    local graphics=type(value.graphics)=='table'and value.graphics or{}
    local distance=graphics.renderDistance
    result.graphics={renderDistance=({[10]=true,[14]=true,[20]=true,[28]=true})[distance]and distance or 0}
    local localPlay=type(value.localPlay)=='table' and value.localPlay or {}
    result.localPlay={connectionMode=CONNECTION_MODES[localPlay.connectionMode] and localPlay.connectionMode or 'auto',
        autoJoin=localPlay.autoJoin==true}
    local source=type(value.audio)=="table" and value.audio or {}
    for key,default in pairs(AUDIO) do
        local entry=source[key]
        if type(default)=="number" then
            result.audio[key]=type(entry)=="number" and entry==entry and math.max(0,math.min(1,entry)) or default
        else result.audio[key]=type(entry)=="boolean" and entry or default end
    end
    if source.stationOverride=="8bit" or source.stationOverride=="chill" or source.stationOverride=="vibes" then
        result.audio.stationOverride=source.stationOverride
    end
    if type(source.rainOverride)=="boolean" then result.audio.rainOverride=source.rainOverride end
    local accessibility=type(value.accessibility)=="table" and value.accessibility or {}
    for key in pairs(Accessibility.defaults) do result.accessibility[key]=accessibility[key] end
    if type(accessibility.reducedFlashes)=="boolean" then result.accessibility.reducedFlashes=accessibility.reducedFlashes end
    Accessibility.ensure(result)
    return result
end

local function decode(text)
    if type(text)~="string" or #text>LIMITS.maxBytes then return nil end
    local value=Codec.decode(text,LIMITS)
    if type(value)~="table" or value.version~=1 or type(value.audio)~="table" or type(value.accessibility)~="table" then return nil end
    return normalized(value)
end

function Preferences.new(filesystem)
    assert(type(filesystem)=="table","preferences require a filesystem")
    local self=setmetatable({filesystem=filesystem,values=normalized(),persisted=false},Store)
    for _,path in ipairs({Preferences.PATH,Preferences.PATH..".tmp"}) do
        local ok,text=pcall(filesystem.read,path)
        local values=ok and decode(text)
        if values then self.values=values; self.persisted=true; break end
    end
    self.menu=self:bind(nil,function() return "offline" end)
    return self
end

function Store:save(configured)
    if configured then self.values.configured=true end
    local payload,errorMessage=Codec.encode(normalized(self.values),LIMITS)
    if not payload then self.lastError=errorMessage; return false end
    local fs=self.filesystem
    local function checked(path)
        local ok,result=pcall(fs.write,path,payload)
        if not ok or not result then return false end
        local readOk,text=pcall(fs.read,path)
        return readOk and text==payload and decode(text)~=nil
    end
    local temporary=Preferences.PATH..".tmp"
    if not checked(temporary) or not checked(Preferences.PATH) then
        self.lastError="Local settings could not be saved. Changes will retry on close."
        return false
    end
    if fs.remove then pcall(fs.remove,temporary) end
    self.persisted=true; self.lastError=nil
    return true
end

function Store:localPlay()
    local value=self.values.localPlay
    return {connectionMode=value.connectionMode,autoJoin=value.autoJoin}
end
function Store:setLocalPlay(value)
    if type(value)~='table' or not CONNECTION_MODES[value.connectionMode] or type(value.autoJoin)~='boolean' then return false end
    for key in pairs(value) do if key~='connectionMode' and key~='autoJoin' then return false end end
    self.values.localPlay={connectionMode=value.connectionMode,autoJoin=value.autoJoin}
    return self:save()
end

function Store:bind(data,mode)
    local selfStore=self
    -- Lua 5.1 weak-key tables are not ephemerons: a value that points back
    -- to its key would retain every campaign opened by this device.
    local campaign=setmetatable({data},{__mode="v"})
    local owner=setmetatable({self},{__mode="v"})
    local audio=setmetatable({}, {
        __index=function(_,key)
            local values=selfStore.values.audio
            local source=campaign[1]
            local shared=source and source.audio or {}
            if key=="station" then return values.stationOverride or shared.station or "chill" end
            if key=="rainEnabled" then
                if values.rainOverride~=nil then return values.rainOverride end
                return shared.rainEnabled==nil and true or shared.rainEnabled
            end
            return values[key]
        end,
        __newindex=function(_,key,value)
            if key=="station" then selfStore.values.audio.stationOverride=AudioCatalog.normalizeStation(value)
            elseif key=="rainEnabled" then selfStore.values.audio.rainOverride=value==true
            elseif AUDIO[key]~=nil then selfStore.values.audio[key]=value
            else error("unknown local audio setting: "..tostring(key)) end
        end,
    })
    local view={audio=audio,accessibility=self.values.accessibility,graphics=self.values.graphics}
    local binding={owner=owner,view=view}
    if data then bindings[data]=binding; Accessibility.bind(data,self.values.accessibility,mode) end
    bindings[view]={owner=owner}; Accessibility.bind(view,self.values.accessibility,mode)
    return view
end

function Store:attach(data,mode)
    mode=mode or function() return "offline" end
    local own=mode()~="client"
    if own and not self.values.configured then
        local legacy=normalized({configured=true,audio=data.audio,accessibility=data.accessibility})
        -- Keep existing view references when importing the first own campaign.
        for key in pairs(self.values.audio) do self.values.audio[key]=nil end
        for key,value in pairs(legacy.audio) do self.values.audio[key]=value end
        for key in pairs(self.values.accessibility) do self.values.accessibility[key]=nil end
        for key,value in pairs(legacy.accessibility) do self.values.accessibility[key]=value end
        self.values.configured=true
    end
    local view=self:bind(data,mode)
    if own and self:save() then
        data.coop.preferencesDetached=true
        data.accessibility=nil
        local shared=data.audio or {}
        data.audio={station=AudioCatalog.normalizeStation(shared.station),rainEnabled=shared.rainEnabled==true}
    end
    return view
end

local function binding(data)
    local value=data and bindings[Players.campaignOf(data)]
    return value,value and value.owner[1]
end
function Preferences.view(data)
    local value=binding(data); return value and value.view or data
end
function Preferences.audio(data)
    local view=Preferences.view(data); return view and view.audio
end
function Preferences.followRadio(data)
    local _,owner=binding(data)
    if owner then
        owner.values.audio.stationOverride=nil; owner.values.audio.rainOverride=nil
        return owner:save(true)
    end
    return false
end
function Preferences.hasOverride(data)
    local _,owner=binding(data)
    return owner and (owner.values.audio.stationOverride~=nil or owner.values.audio.rainOverride~=nil) or false
end
return Preferences
