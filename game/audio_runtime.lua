local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"audio runtime requires "..name)
  if expected then assert(type(value)==expected,"audio runtime "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","audio runtime requires a context")
  local runtime=required(context,"runtime","table")
  local ui=required(context,"ui","table")
  local Catalog=required(context,"catalog","table")
  local Audio=required(context,"audio","table")
  local audio
  local departSource

  local function initialize()
      if audio then audio:shutdown() end
      audio=Audio.new()
      audio:installGunPools()
      return audio
  end

  local function settings()
      return runtime.saveData and runtime.saveData.audio
  end

  local function musicCategory()
      if runtime.state=="ending" then return "endingHappy" end
      if runtime.state=="battle" then return runtime.battle and runtime.battle.encounter and runtime.battle.encounter.tier=="hard" and "bossFight" or "battle" end
      if runtime.scene=="house" then return "insideHomes" end
      if runtime.scene=="stop" or runtime.state=="event" then return "stops" end
      return "train"
  end

  local function playSfx(kind)
      local current=settings()
      if audio and current then return audio:playSfx(kind,current,runtime.battle) end
  end

  local function playTrainDepart()
      departSource=playSfx("trainDepart")
      return departSource
  end

  local function weaponSfx(weaponName,combat)
      if weaponName=="trail-slingshot" or weaponName=="scrap-boomerang" or combat.ammo=="arrows" then return "bow" end
      if combat.kind~="ranged" then return weaponName=="scratch" and "slash" or "sword" end
      local tier=(Catalog.weaponStats[weaponName] and Catalog.weaponStats[weaponName].tier) or 1
      return tier<=4 and "gunshotLight" or (tier<=6 and "gunshotMedium" or "gunshotHeavy")
  end

  local function update()
      local current=settings()
      if audio and current then audio:update(current,musicCategory()) end
  end

  local function resetMusic()
      if audio then audio:resetMusic(); return true end
      return false
  end

  local function previousTrack()
      local current=settings()
      return audio and current and audio:previousTrack(current,musicCategory()) or false
  end

  local function togglePause()
      local current=settings()
      return audio and current and audio:togglePause(current) or false
  end

  local function nextTrack()
      local current=settings()
      return audio and current and audio:nextTrack(current,musicCategory()) or false
  end

  local function toggleMute()
      local current=settings()
      return audio and current and audio:toggleMute(current) or false
  end

  local function status()
      return {
          available=audio~=nil,
          lastError=audio and audio.lastError or nil,
          nowPlaying=audio and audio.nowPlaying or nil,
      }
  end

  local function shutdown()
      if audio then audio:shutdown(); audio=nil end
      departSource=nil
  end

  ui.playSfx=playSfx
  ui.weaponSfx=weaponSfx

  return {
      initialize=initialize,
      playSfx=playSfx,
      playTrainDepart=playTrainDepart,
      weaponSfx=weaponSfx,
      musicCategory=musicCategory,
      update=update,
      resetMusic=resetMusic,
      previousTrack=previousTrack,
      togglePause=togglePause,
      nextTrack=nextTrack,
      toggleMute=toggleMute,
      status=status,
      shutdown=shutdown,
  }
end

return {new=new}
