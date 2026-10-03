-- Pure persisted crafting model. UI timing, rendering, and input live elsewhere.
local Definitions = require("game.outfit_catalog")
local Crafting = {}

local function finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function integer(value,minimum,fallback)
    return finite(value) and math.max(minimum,math.floor(value)) or fallback
end
local function response(ok,message,fields)
    local result=fields or {}
    result.ok=ok
    result.message=message
    if result.changed==nil then result.changed=false end
    return result
end

function Crafting.ensure(data)
    if type(data)~="table" then return nil end
    if type(data.outfitCrafting)~="table" then data.outfitCrafting={} end
    local state=data.outfitCrafting
    state.version=1
    local project=state.project
    if type(project)=="table" and Definitions.recipesById[project.recipeId] then
        local recipe=Definitions.recipesById[project.recipeId]
        project.stageIndex=math.min(#recipe.stages+1,integer(project.stageIndex,1,1))
        project.pointIndex=integer(project.pointIndex,1,1)
        local stage=recipe.stages[project.stageIndex]
        if stage then project.pointIndex=math.min(stage.kind=="tension" and 1 or #stage.points,project.pointIndex) end
        project.mistakes=integer(project.mistakes,0,0)
        project.attempts=integer(project.attempts,0,0)
        project.correctActions=integer(project.correctActions,0,0)
        project.complete=project.stageIndex>#recipe.stages
    end
    return state
end

function Crafting.project(data)
    local state=Crafting.ensure(data)
    return state and type(state.project)=="table" and state.project or nil
end

local function inventorySlots(data)
    local slots={}
    for index,name in pairs(type(data.inventory)=="table" and data.inventory or {}) do
        if finite(index) and index>=1 and index==math.floor(index) and type(name)=="string" then slots[#slots+1]=index end
    end
    table.sort(slots)
    return slots
end

function Crafting.status(data,recipeId)
    local state=Crafting.ensure(data)
    if not state then return response(false,"No character is available.",{canStart=false,materials={}}) end
    local recipe=Definitions.recipesById[recipeId]
    if not recipe then return response(false,"That outfit pattern is unavailable.",{canStart=false,materials={}}) end
    local counts={}
    for _,index in ipairs(inventorySlots(data)) do
        local id=data.inventory[index]
        counts[id]=(counts[id] or 0)+1
    end
    local materials,missingCount={},0
    for _,cost in ipairs(recipe.materials) do
        local have=counts[cost.id] or 0
        local missing=math.max(0,cost.count-have)
        materials[#materials+1]={id=cost.id,label=Definitions.materials[cost.id].label,count=cost.count,have=have,missing=missing}
        missingCount=missingCount+missing
    end
    local hasProject=state.project~=nil
    local reason=hasProject and "Finish the project already on the bench first."
        or missingCount>0 and "Gather the missing material bundles in your backpack." or nil
    return response(true,reason,{canStart=not reason,reason=reason,recipe=recipe,materials=materials,
        missingCount=missingCount,hasProject=hasProject})
end

function Crafting.start(data,recipeId)
    local status=Crafting.status(data,recipeId)
    if not status.canStart then return response(false,status.reason or status.message) end
    local needed={}
    for _,cost in ipairs(status.recipe.materials) do needed[cost.id]=cost.count end
    local committed={}
    for _,index in ipairs(inventorySlots(data)) do
        local id=data.inventory[index]
        if (needed[id] or 0)>0 then committed[#committed+1]=index; needed[id]=needed[id]-1 end
    end
    -- Select every bundle before removing any. No partial consumption on failure.
    for _,amount in pairs(needed) do if amount>0 then return response(false,"Materials changed. Gather all required bundles first.") end end
    for _,index in ipairs(committed) do data.inventory[index]=nil end
    data.outfitCrafting.project={recipeId=recipeId,stageIndex=1,pointIndex=1,completedPoints=0,
        correctActions=0,mistakes=0,attempts=0,complete=false}
    return response(true,"Materials set aside. Mark the first panel.",{changed=true,project=data.outfitCrafting.project})
end

function Crafting.stage(data)
    local project=Crafting.project(data)
    local recipe=project and Definitions.recipesById[project.recipeId]
    if not recipe or project.complete then return nil end
    local source=recipe.stages[project.stageIndex]
    if not source then return nil end
    local stage={}
    for key,value in pairs(source) do stage[key]=value end
    stage.pointIndex=project.pointIndex
    stage.progress=project.pointIndex-1
    stage.total=stage.kind=="tension" and 1 or #stage.points
    stage.currentPoint=stage.points and stage.points[project.pointIndex] or nil
    stage.stageIndex=project.stageIndex
    stage.stageCount=#recipe.stages
    return stage
end

function Crafting.quality(data)
    local project=Crafting.project(data)
    if not project then return nil end
    local recipe=Definitions.recipesById[project.recipeId]
    if not recipe then return nil end
    local score=math.max(0,100-math.floor(project.mistakes*100/math.max(1,recipe.totalActions)))
    return score>=96 and "masterwork" or score>=80 and "fine" or "usable",score
end

function Crafting.act(data,action)
    local project=Crafting.project(data)
    local stage=Crafting.stage(data)
    if not project or not stage then return response(false,project and "The project is ready to collect." or "Choose a pattern first.") end
    if type(action)~="table" or action.kind~=stage.kind then return response(false,"Use the tool for the current step.") end
    local correct=false
    if stage.kind=="point" then
        if not finite(action.x) or not finite(action.y) then return response(false,"Choose the next marked point.") end
        local target=stage.currentPoint
        local dx,dy=action.x-target.x,action.y-target.y
        correct=dx*dx+dy*dy<=stage.tolerance*stage.tolerance
    elseif stage.kind=="tension" then
        if not finite(action.value) then return response(false,"Set the seam tension.") end
        correct=action.value>=stage.targetRange.min and action.value<=stage.targetRange.max
    end
    project.attempts=project.attempts+1
    if not correct then
        project.mistakes=project.mistakes+1
        local message=stage.kind=="point" and "Reposition the tool at the highlighted mark and try again."
            or action.value<stage.targetRange.min and "The seam is too loose. Draw it snug and try again."
            or "The seam is pulled too tight. Ease the thread and try again."
        return response(true,message,{changed=true,correct=false,complete=false,stageComplete=false})
    end
    project.correctActions=project.correctActions+1
    project.completedPoints=project.correctActions
    project.pointIndex=project.pointIndex+1
    local stageComplete=project.pointIndex>stage.total
    if stageComplete then
        project.stageIndex=project.stageIndex+1
        project.pointIndex=1
    end
    local recipe=Definitions.recipesById[project.recipeId]
    project.complete=project.stageIndex>#recipe.stages
    if project.complete then
        project.quality,project.score=Crafting.quality(data)
        project.outputId=recipe.outputIds[project.quality]
    end
    return response(true,project.complete and "The finished upgrade is ready to collect."
        or stageComplete and "Step complete. Prepare the next tool." or "Good placement.",
        {changed=true,correct=true,complete=project.complete,stageComplete=stageComplete,
            quality=project.quality,outputId=project.outputId})
end

function Crafting.finish(data)
    local project=Crafting.project(data)
    local recipe=project and Definitions.recipesById[project.recipeId]
    if not recipe then return response(false,"There is no project to collect.") end
    if not project.complete then return response(false,"Complete every crafting step before collecting the upgrade.") end
    local capacity=integer(data.inventoryCapacity,1,6)
    data.inventory=data.inventory or {}
    local slot
    for index=1,capacity do if data.inventory[index]==nil then slot=index; break end end
    if not slot then return response(false,"Free one backpack slot. Your finished work will stay on the bench.",{inventoryFull=true,complete=true}) end
    local quality,score=Crafting.quality(data)
    local outputId=recipe.outputIds[quality]
    data.inventory[slot]=outputId
    data.outfitCrafting.project=nil
    return response(true,Definitions.upgrades[outputId].label.." added to your backpack.",
        {changed=true,complete=true,outputId=outputId,quality=quality,score=score,slot=slot})
end

return Crafting
