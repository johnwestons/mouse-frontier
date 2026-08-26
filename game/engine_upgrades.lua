local EngineUpgrades = {}

EngineUpgrades.tiers = {
    {name="Stock Engine",cost=0,coal=1.00,supplies=1.00,speed=1.00,wearReduction=0,description="Original patched-together locomotive."},
    {name="Tuned Firebox",cost=15,unlockStop=5,coal=.90,supplies=.95,speed=1.08,wearReduction=0,description="10% less coal and shorter journeys."},
    {name="Rebuilt Boiler",cost=28,unlockStop=14,coal=.80,supplies=.90,speed=1.18,wearReduction=1,description="20% less coal, fewer provisions, and wear -1."},
    {name="High-Pressure Drive",cost=45,unlockStop=26,coal=.68,supplies=.82,speed=1.30,wearReduction=1,description="32% less coal, 18% fewer provisions, and wear -1."},
    {name="Frontier Express",cost=70,unlockStop=38,coal=.55,supplies=.72,speed=1.45,wearReduction=2,description="45% less coal, 28% fewer provisions, and wear -2."}
}

function EngineUpgrades.profile(level)
    return EngineUpgrades.tiers[math.max(1,math.min(#EngineUpgrades.tiers,(level or 0)+1))]
end

function EngineUpgrades.next(level)
    return EngineUpgrades.tiers[(level or 0)+2]
end

function EngineUpgrades.applyCosts(level,food,water,coal)
    local profile=EngineUpgrades.profile(level)
    return math.max(1,math.floor(food*profile.supplies)),math.max(1,math.floor(water*profile.supplies)),math.max(1,math.ceil(coal*profile.coal))
end

function EngineUpgrades.timings(level,condition)
    local conditionSpeed=(condition or 100)<25 and .82 or ((condition or 100)<50 and .92 or 1)
    local speed=EngineUpgrades.profile(level).speed*conditionSpeed
    return {
        depart=1.55/speed,
        fadeOut=1.15/speed,
        change=2.00/speed,
        arrive=2.45/speed,
        arrivalDuration=2.05/speed,
        total=4.50/speed,
        fadeDuration=.65/speed,
        finishFade=.80/speed
    }
end

return EngineUpgrades
