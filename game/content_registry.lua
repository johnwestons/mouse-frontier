local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"content registry requires "..name)
  if expected then assert(type(value)==expected,"content registry "..name.." must be a "..expected) end
  return value
end

local targetNames={
  "ui","scenery","characters","characterImages","npcImages","mobImages","mobFiles","backgroundImages",
  "characterWalkImages","npcWalkImages","characterActionImages","mobAttackImages","mobIdleImages","mobHitImages",
  "mobDeathImages","mobWalkImages","mobRangedImages","familyImages","itemIdleImages",
}

local legacyAnimationNames={
  "characterWalkImages","npcWalkImages","characterActionImages","mobAttackImages","mobIdleImages","mobHitImages",
  "mobDeathImages","mobWalkImages","mobRangedImages","npcImages","mobImages",
}

local function new(context)
  assert(type(context)=="table","content registry requires an explicit context")
  local Filesystem=required(context,"filesystem","table")
  assert(type(Filesystem.getInfo)=="function","content registry filesystem requires getInfo")

  local registry={}
  local assetTargets={}
  for _,name in ipairs(targetNames) do
    local collection={}
    registry[name]=collection
    assetTargets[name]=collection
  end
  registry.assetTargets=assetTargets

  local legacyAnimationTables={}
  for _,name in ipairs(legacyAnimationNames) do
    legacyAnimationTables[#legacyAnimationTables+1]=registry[name]
  end
  registry.legacyAnimationTables=legacyAnimationTables

  function registry.isFurnitureItem(name)
    return type(name)=="string" and name~="" and Filesystem.getInfo("assets/sprites/furniture/"..name..".png")~=nil
  end

  function registry.status()
    local linked=true
    for _,name in ipairs(targetNames) do
      if assetTargets[name]~=registry[name] then linked=false; break end
    end
    return {
      hydrated=#registry.characters>0 and #registry.mobFiles>0 and type(registry.ui.propImages)=="table" and type(registry.scenery.cloudImages)=="table",
      targetsLinked=linked,
      targetCount=#targetNames,
      legacyAnimationCount=#legacyAnimationTables,
    }
  end

  return registry
end

return {new=new}
