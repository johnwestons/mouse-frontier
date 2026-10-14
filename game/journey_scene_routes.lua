-- Shared host route policy. Scene transactions call this on their detached
-- draft; local entrance presentation uses the same scheduling exclusions.
local Range=require('game.shooting_range')
local Events=require('game.events')
local Areas=require('game.expedition_areas')
local Caravan=require('game.crow_caravan_area')
local Routes={}
function Routes.caravanSchedule(data,rng)
    local excluded={[1]=true,[50]=true}
    for _,stop in ipairs(Range.hostStops or {}) do excluded[stop]=true end
    for _,stop in ipairs(Events.storyStops or {}) do excluded[stop]=true end
    for _,stop in ipairs(data.mysteryStops or {}) do excluded[stop]=true end
    for stop=1,50 do
        if Areas.availableAtStop(stop) or not Caravan.hasStopGate(stop) then excluded[stop]=true end
    end
    return {excludedStops=excluded,rng=rng}
end
return Routes
