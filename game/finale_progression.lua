local Finale={}

Finale.choices={
    {id="haven",title="BUILD A SAFE HAVEN",description="Turn the valley depot into a home for travelers and separated families."},
    {id="family",title="REST WITH YOUR FAMILY",description="Let the engine cool and give your reunited family the time they lost."},
    {id="lifeline",title="KEEP THE TRAIN RUNNING",description="Invite your family aboard and carry relief back along the rails."},
}

local outcomes={
    haven="The depot becomes an open door: a safe bed, a shared meal, and a message board where scattered families find one another.",
    family="The train finally rests beneath the valley trees while your family rebuilds a home around the engine that brought you back together.",
    lifeline="Your family climbs aboard. Together, you turn the old train east again, carrying medicine, letters, and hope to every stop behind you.",
}

local tiers={
    {minimum=90,name="FRONTIER BEACON",text="Your arrival changes more than one valley. The network you built becomes a promise that no settlement has to stand alone."},
    {minimum=55,name="RAILWAY OF HOPE",text="Friends already know your whistle. The railway becomes a trusted path between families, farms, and safe settlements."},
    {minimum=0,name="HOME AT LAST",text="The journey ends in safety and reunion. The kindness you managed along the way gives the valley somewhere good to begin."},
}

local function countHistory(data,kind)
    local count=0
    for _,entry in ipairs(data.helpHistory or {}) do if not kind or entry.kind==kind then count=count+1 end end
    return count
end

function Finale.choice(id)
    for _,choice in ipairs(Finale.choices) do if choice.id==id then return choice end end
end

function Finale.evaluate(data,StopHelp,Maintenance)
    data=data or {}
    local goodwill=StopHelp.status(data)
    local story=math.max(0,math.min(10,math.floor(tonumber(data.eventProgress and data.eventProgress.story) or 0)))
    local mystery=math.max(0,math.min(5,math.floor(tonumber(data.eventProgress and data.eventProgress.mystery) or 0)))
    local helpCount=countHistory(data)
    local rides=countHistory(data,"ride")
    local condition=math.floor(Maintenance.condition(data)+.5)
    local cars=math.max(1,#(data.trainCars or {}))
    local level=math.max(1,math.floor(tonumber(data.stats and data.stats.level) or 1))
    local score=goodwill.points*3+story*3+mystery*2+math.min(20,helpCount)*2+rides*2+math.floor(condition/10)+cars*2+level
    local tier=tiers[#tiers]
    for _,candidate in ipairs(tiers) do if score>=candidate.minimum then tier=candidate; break end end
    local reunion
    if story>=10 then reunion="The ten clues lead straight to the California valley. Your family is waiting beside the three-line mark from the trail."
    elseif story>=5 then reunion="The clues run thin near the valley, but the settlers you helped carry your name ahead. At the depot, your family recognizes the old red engine."
    else reunion="You reach the valley with only fragments of the trail. Word passed between travelers and settlements does what the missing clues could not: your family finds your train." end
    local selected=data.finale and Finale.choice(data.finale.choice)
    return {score=score,tier=tier.name,tierText=tier.text,reunion=reunion,choice=selected,
        outcome=selected and outcomes[selected.id] or nil,goodwill=goodwill.points,goodwillTier=goodwill.tier,
        storyClues=story,mysteryClues=mystery,helpCount=helpCount,rides=rides,condition=condition,cars=cars,level=level}
end

function Finale.choose(data,id)
    local choice=Finale.choice(id)
    if not choice then return false end
    data.finale=type(data.finale)=="table" and data.finale or {}
    if data.finale.choice then return data.finale.choice==id end
    data.finale.choice=id; data.finale.completed=true
    return true
end

function Finale.audit(StopHelp,Maintenance)
    local low={goodwill=0,helpHistory={},eventProgress={story=0,mystery=0},trainCars={"living-car"},stats={level=1},maintenance={condition=18}}
    local middle={goodwill=8,helpHistory={},eventProgress={story=6,mystery=2},trainCars={"living-car","greenhouse","medical"},stats={level=6},maintenance={condition=58}}
    for index=1,6 do middle.helpHistory[index]={kind=index<=2 and "ride" or "item",points=1,location=index} end
    local high={goodwill=25,helpHistory={},eventProgress={story=10,mystery=5},trainCars={"living-car","coal-hauler","storage","greenhouse","sleeper","medical","navigator"},stats={level=12},maintenance={condition=96}}
    for index=1,12 do high.helpHistory[index]={kind=index<=4 and "ride" or "first-aid",points=1,location=index} end
    local a,b,c=Finale.evaluate(low,StopHelp,Maintenance),Finale.evaluate(middle,StopHelp,Maintenance),Finale.evaluate(high,StopHelp,Maintenance)
    local choicesReady=#Finale.choices==3 and Finale.choose(middle,"lifeline") and not Finale.choose(middle,"haven")
    local selected=Finale.evaluate(middle,StopHelp,Maintenance)
    local ready=a.tier=="HOME AT LAST" and b.tier=="RAILWAY OF HOPE" and c.tier=="FRONTIER BEACON"
        and a.score<b.score and b.score<c.score and choicesReady and selected.choice.id=="lifeline"
        and a.storyClues==0 and c.storyClues==10 and c.condition==96 and c.cars==7 and c.level==12
    return {ready=ready,low=a,middle=b,high=c,choiceCount=#Finale.choices,selected=selected.choice and selected.choice.id,
        positiveOnly=not (a.tier..b.tier..c.tier):lower():find("evil",1,true),curve="finale-v1"}
end

return Finale
