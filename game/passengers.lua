local Passengers = {}

function Passengers.jobFor(file)
    local name=(file or ""):lower()
    if name:find("botanist") or name:find("flower") then return "greenhouse" end
    if name:find("engineer") or name:find("mechanic") or name:find("conductor") then return "fireman" end
    if name:find("medic") then return "medic" end
    return "scavenger"
end

function Passengers.preferredCar(passenger,trainCars)
    local wanted=Passengers.preferredCarId(passenger.job)
    for index,id in ipairs(trainCars or {}) do
        if id==wanted then return index end
    end
    return 1
end

function Passengers.preferredCarId(job)
    return job=="greenhouse" and "greenhouse"
        or (job=="fireman" and "coal-hauler"
        or (job=="medic" and "medical" or "sleeper"))
end

function Passengers.rideLength(job,remaining,food,water,randomOffset)
    local base={greenhouse=5,scavenger=3,fireman=4,medic=4}
    local supplyBonus=(food>=8 and water>=8) and 1 or 0
    return math.min(remaining,math.max(1,(base[job] or 3)+supplyBonus+(randomOffset or 0)))
end

return Passengers
