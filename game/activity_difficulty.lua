local Difficulty={}

Difficulty.bands={
    {id="settled",name="SETTLED FARMS",first=1,last=16,rounds=3,maximumMistakes=3,
        palette={panel={.075,.07,.035},accent={.72,.86,.28},ground={.20,.34,.14}},offsets={{0,0},{0,0},{0,0}}},
    {id="drylands",name="DRYLAND CROSSING",first=17,last=33,rounds=4,maximumMistakes=3,
        palette={panel={.10,.052,.026},accent={.96,.58,.20},ground={.38,.23,.10}},offsets={{-18,-18},{0,24},{18,-18}}},
    {id="ashlands",name="ASHLAND FRONTIER",first=34,last=50,rounds=5,maximumMistakes=2,
        palette={panel={.055,.045,.075},accent={.52,.84,.88},ground={.20,.18,.27}},offsets={{20,24},{0,-28},{-20,24}}},
}

function Difficulty.profile(location)
    location=math.max(1,math.min(50,math.floor(tonumber(location) or 1)))
    for _,band in ipairs(Difficulty.bands) do if location<=band.last then return band end end
    return Difficulty.bands[#Difficulty.bands]
end

function Difficulty.apply(session,location)
    local band=Difficulty.profile(location)
    session.difficulty=band; session.rounds=band.rounds; session.maximumMistakes=band.maximumMistakes
    session.progress.difficultyBand=band.id
    return session
end

function Difficulty.audit()
    local early,mid,late=Difficulty.profile(1),Difficulty.profile(25),Difficulty.profile(45)
    return {ready=early.rounds==3 and mid.rounds==4 and late.rounds==5 and early.maximumMistakes==3
            and mid.maximumMistakes==3 and late.maximumMistakes==2 and early.id~=mid.id and mid.id~=late.id,
        bands=3,earlyRounds=early.rounds,midRounds=mid.rounds,lateRounds=late.rounds,lateMistakes=late.maximumMistakes,
        visualVariants=3,curve="activity-difficulty-v1"}
end

return Difficulty
