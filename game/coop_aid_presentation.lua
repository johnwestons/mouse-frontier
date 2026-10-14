-- Build a detached display from known projected progress; never call the
-- treatment model's normalizers, gesture rules or update loop on a replica.
local Presentation={}
local function number(value,max)
    return type(value)=='number' and value==value and math.max(0,math.min(max,value)) or 0
end
function Presentation.new(facts,data,npc,progressSource)
    local quest=data.helpQuestSessions and data.helpQuestSessions[facts.questId]
    local source=progressSource or quest and quest.progress or {}
    local progress={phase=facts.phase,stage=facts.phase,pourTime=number(source.pourTime,.8),rubDistance=number(source.rubDistance,220),
        rubTurns=math.floor(number(source.rubTurns,3)),ointmentDistance=number(source.ointmentDistance,180),ointmentTrail={},
        gauzePlaced=source.gauzePlaced==true,wrapPasses=math.floor(number(source.wrapPasses,3)),
        wrapArmed=source.wrapArmed==true,wrapDirection=source.wrapDirection==-1 and -1 or 1}
    for i=1,math.min(80,#(type(source.ointmentTrail)=='table' and source.ointmentTrail or {})) do
        local point=source.ointmentTrail[i]
        if type(point)=='table' and type(point.x)=='number' and type(point.y)=='number'
            and point.x==point.x and point.y==point.y and point.x>=-4096 and point.x<=4096 and point.y>=-4096 and point.y<=4096 then
            progress.ointmentTrail[#progress.ointmentTrail+1]={x=point.x,y=point.y}
        end
    end
    return {npc=npc,itemName=facts.itemName,phase=facts.phase,stage=facts.phase,progress=progress,
        ready=facts.ready,dragging=facts.dragging,pointer={x=facts.pointer.x,y=facts.pointer.y},helpQuestId=facts.questId}
end
return Presentation
