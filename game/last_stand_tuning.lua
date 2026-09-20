local Tuning={
    holdSeconds=180,
    requiredKills=15,
    assistanceSeconds=240,
    withdrawalSeconds=5,
    suppressionInterval=8,
    phaseMoraleLoss=6,
    coverSeconds=.28,
    hitRecoverySeconds=.9,
    hitChance=.12,
    hitChancePerPhase=.025,
    phases={
        {start=0,name="Finding the rhythm",active=2},
        {start=45,name="Crossfire",active=3,intermission=true,
            line="Intermission: check ammunition and wounded defenders in the yard."},
        {start=105,name="Holding under pressure",active=5,intermission=true,
            line="Intermission: additional shooters are moving to the upper floor."},
        {start=165,name="Breaking their nerve",active=4},
    },
}

function Tuning.phase(elapsed)
    for index=#Tuning.phases,1,-1 do
        if elapsed>=Tuning.phases[index].start then return index,Tuning.phases[index].name end
    end
    return 1,Tuning.phases[1].name
end

function Tuning.pressure(morale)
    local remaining=math.max(0,math.min(100,tonumber(morale) or 100))/100
    return .2+.8*remaining
end

function Tuning.spawnDelay(morale)
    local remaining=math.max(0,math.min(100,tonumber(morale) or 100))/100
    return .25+1.75*(1-remaining)
end

return Tuning
