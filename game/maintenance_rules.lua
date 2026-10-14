-- Service progress and payment without rendering, input, particles or cursors.
local Rules={DOSES={2,1,2},OIL_COST=5,RESTORE=40}
local function clamp(value,low,high) return math.max(low,math.min(high,value)) end

function Rules.ensure(data)
    data.maintenance=type(data.maintenance)=="table" and data.maintenance or {}
    local state=data.maintenance
    state.condition=clamp(tonumber(state.condition) or 72,0,100)
    state.lastServicedStop=math.max(0,math.floor(tonumber(state.lastServicedStop) or 0))
    state.totalServices=math.max(0,math.floor(tonumber(state.totalServices) or 0))
    state.totalWear=math.max(0,math.floor(tonumber(state.totalWear) or 0))
    return state
end

function Rules.oilSupply(data)
    data.resources=type(data.resources)=="table" and data.resources or {}
    data.resources.oil=math.max(0,math.floor(tonumber(data.resources.oil) or 0))
    return data.resources.oil
end

function Rules.new(data)
    local completed=Rules.ensure(data).lastServicedStop==(data.location or 1)
    local doses={}; for index,amount in ipairs(Rules.DOSES) do doses[index]=completed and amount or 0 end
    return {open=true,completed=completed,targetDoses=doses,location=data.location or 1}
end

function Rules.progressCount(session)
    local total=0
    for index,amount in ipairs(Rules.DOSES) do total=total+clamp(session.targetDoses[index] or 0,0,amount) end
    return total
end

function Rules.point(session,index,data)
    if not session.open or session.completed or not Rules.DOSES[index] then return {ok=false,reason="unavailable"} end
    if session.location and session.location~=(data.location or 1) then return {ok=false,reason="location"} end
    if (session.targetDoses[index] or 0)>=Rules.DOSES[index] then return {ok=false,reason="full"} end
    if Rules.oilSupply(data)<Rules.progressCount(session)+1 then return {ok=false,reason="oil"} end
    session.targetDoses[index]=(session.targetDoses[index] or 0)+1
    return {ok=true,targetDoses=session.targetDoses}
end

function Rules.complete(session,data)
    local state=Rules.ensure(data)
    if session.completed or state.lastServicedStop==(data.location or 1) then return {ok=false,reason="already"} end
    if not session.open or (session.location and session.location~=(data.location or 1)) then return {ok=false,reason="location"} end
    if Rules.progressCount(session)<Rules.OIL_COST then return {ok=false,reason="progress"} end
    if Rules.oilSupply(data)<Rules.OIL_COST then return {ok=false,reason="oil"} end
    local before=state.condition
    state.condition=clamp(state.condition+Rules.RESTORE,0,100)
    state.lastServicedStop=math.max(1,math.floor(tonumber(data.location) or 1))
    state.totalServices=state.totalServices+1
    data.resources.oil=data.resources.oil-Rules.OIL_COST
    session.completed=true
    return {ok=true,before=before,condition=state.condition,cost=Rules.OIL_COST}
end

return Rules
