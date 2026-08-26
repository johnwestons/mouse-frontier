local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"startup runtime requires "..name)
  if expected then assert(type(value)==expected,"startup runtime "..name.." must be a "..expected) end
  return value
end

local function copy(source)
  local target={}
  for key,value in pairs(source) do target[key]=value end
  return target
end

local function new(context)
  assert(type(context)=="table","startup runtime requires a context")
  local ui=required(context,"ui","table")
  local scenery=required(context,"scenery","table")
  local Graphics=required(context,"graphics","table")
  local Filesystem=required(context,"filesystem","table")
  local Assets=required(context,"assets","table")
  local Settlements=required(context,"settlements","table")
  local Clouds=required(context,"clouds","table")
  local AssetStreamer=required(context,"assetStreamer","table")
  local GameplayUpdate=required(context,"gameplayUpdate","table")
  local assetTargets=required(context,"assetTargets","table")
  local legacyAnimationTables=required(context,"legacyAnimationTables","table")
  local gameplayContext=required(context,"gameplayContext","table")
  local initializeAudio=required(context,"initializeAudio","function")
  local initializeMobile=required(context,"initializeMobile","function")
  local createIntro=required(context,"createIntro","function")

  assert(type(Assets.load)=="function","startup runtime assets must provide load")
  assert(type(Settlements.load)=="function","startup runtime settlements must provide load")
  assert(type(Clouds.new)=="function","startup runtime clouds must provide new")
  assert(type(AssetStreamer.new)=="function","startup runtime asset streamer must provide new")
  assert(type(GameplayUpdate.new)=="function","startup runtime gameplay update must provide new")

  local loaded=false
  local characterAnimations={}
  local cloudLayer
  local gameplayUpdate

  local function loadImage(path)
      local ok,image=pcall(Graphics.newImage,path)
      return ok and image or nil
  end

  local function load()
      if loaded then return false end
      Graphics.setDefaultFilter("nearest","nearest")
      Graphics.setFont(Graphics.newFont(16))
      initializeAudio()
      Filesystem.createDirectory("saves")

      characterAnimations=Assets.load(assetTargets)
      ui.introCinematic=createIntro()
      cloudLayer=Clouds.new(scenery.cloudImages)
      scenery.settlements=Settlements.load(loadImage)
      ui.assetStreamer=AssetStreamer.new({
          settlements=scenery.settlements,
          interiorFiles=scenery.interiorFiles,
          characterAnimations=characterAnimations,
          legacyAnimationTables=legacyAnimationTables,
      })
      initializeMobile()

      local updateContext=copy(gameplayContext)
      updateContext.cloudLayer=cloudLayer
      gameplayUpdate=GameplayUpdate.new(updateContext)
      loaded=true
      return true
  end

  local function update(dt)
      assert(gameplayUpdate,"startup runtime must be loaded before update")
      return gameplayUpdate.update(dt)
  end

  local function isLoaded() return loaded end
  local function getCharacterAnimations() return characterAnimations end
  local function getCloudLayer() return cloudLayer end

  return {
      load=load,
      update=update,
      isLoaded=isLoaded,
      characterAnimations=getCharacterAnimations,
      cloudLayer=getCloudLayer,
  }
end

return {new=new}
