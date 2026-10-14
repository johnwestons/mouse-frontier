-- Saved treatment progress; leases, pointers and held gestures are ephemeral.
local P=require('game.net.protocol')
local State={VERSION=1}
local fields={phase=true,stage=true,pourTime=true,rubDistance=true,rubTurns=true,ointmentDistance=true,
    ointmentTrail=true,gauzePlaced=true,wrapPasses=true,wrapArmed=true,wrapDirection=true}
local function number(n,low,high) return type(n)=='number' and n==n and n>=low and n<=high end
function State.validProgress(progress)
    if not P.fields(progress,fields) or not P.integer(progress.phase,1,6) or progress.stage~=progress.phase
        or not number(progress.pourTime,0,.8) or not number(progress.rubDistance,0,1e9)
        or not P.integer(progress.rubTurns,0,1e9) or not number(progress.ointmentDistance,0,1e9)
        or type(progress.gauzePlaced)~='boolean' or not P.integer(progress.wrapPasses,0,3)
        or type(progress.wrapArmed)~='boolean' or progress.wrapDirection~=1 and progress.wrapDirection~=-1
        or type(progress.ointmentTrail)~='table' or #progress.ointmentTrail>80 then return false end
    local count=0
    for i,point in pairs(progress.ointmentTrail) do
        if not P.integer(i,1,#progress.ointmentTrail) or not P.fields(point,{x=true,y=true})
            or not number(point.x,-4096,4096) or not number(point.y,-4096,4096) then return false end
        count=count+1
    end
    return count==#progress.ointmentTrail
end
function State.validate(data)
    local quest=data.lastStand; if not quest then return true end
    if quest.treatmentVersion==nil then return quest.treatmentProgress==nil or type(quest.treatmentProgress)=='table' end
    return quest.treatmentVersion==State.VERSION and (quest.treatmentProgress==nil or State.validProgress(quest.treatmentProgress))
end
local function clean(n,high,integer)
    n=tonumber(n); n=number(n,0,1e9) and math.min(high,n) or 0
    return integer and math.floor(n) or n
end
function State.prepare(data)
    local quest=data.lastStand
    if not quest or quest.treatmentProgress==nil or quest.treatmentVersion~=nil then return end
    local old=quest.treatmentProgress; local phase=math.max(1,clean(old.phase or old.stage,6,true))
    local progress={phase=phase,stage=phase,pourTime=clean(old.pourTime,.8),rubDistance=clean(old.rubDistance,1e9),
        rubTurns=clean(old.rubTurns,1e9,true),ointmentDistance=clean(old.ointmentDistance,1e9),ointmentTrail={},
        gauzePlaced=old.gauzePlaced==true,wrapPasses=clean(old.wrapPasses,3,true),wrapArmed=old.wrapArmed==true,
        wrapDirection=old.wrapDirection==-1 and -1 or 1}
    local trail=type(old.ointmentTrail)=='table' and old.ointmentTrail or {}
    for i=math.max(1,#trail-79),#trail do
        local point=trail[i]
        if P.fields(point,{x=true,y=true}) and number(point.x,-4096,4096) and number(point.y,-4096,4096) then
            progress.ointmentTrail[#progress.ointmentTrail+1]={x=point.x,y=point.y}
        end
    end
    quest.treatmentProgress=progress; quest.treatmentVersion=State.VERSION
end
function State.ensure(data)
    local quest=assert(data.lastStand)
    if not quest.treatmentProgress then quest.treatmentProgress={}; quest.treatmentVersion=nil end
    State.prepare(data); assert(State.validProgress(quest.treatmentProgress),'invalid Last Stand treatment')
    return quest.treatmentProgress
end
function State.ready(progress) return progress.phase==6 and progress.gauzePlaced and progress.wrapPasses==3 end
return State
