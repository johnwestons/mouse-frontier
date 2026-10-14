-- Survey and cache assistance changes the host campaign without moving the party.
local P=require('game.net.protocol')
local Areas=require('game.expedition_areas')
local Players=require('game.coop_players')
local Entities=require('game.coop_entities')
local Commands={}
local function point(value) return type(value)=='number' and value==value and value>-math.huge and value<math.huge end
local function near(data,area,spot,actor)
    return point(actor.x) and point(actor.y) and (actor.x-spot.x)^2+(actor.y-spot.y)^2<=spot.radius^2
        and Areas.canReach(data,area.id,actor.x,actor.y,spot.x,spot.y,true)
end
function Commands.nearest(data,actor)
    local area=Areas.current(data)
    if not area or not actor or actor.scene~='expedition' or data.scene~='expedition' then return nil end
    local best,distance
    for _,spot in ipairs(area.interactions or {}) do
        if (spot.kind=='survey' or spot.kind=='chest') and near(data,area,spot,actor) then
            local d=(actor.x-spot.x)^2+(actor.y-spot.y)^2
            if not distance or d<distance then best,distance=spot,d end
        end
    end
    return best
end
function Commands.scopes(data,id,containerId)
    local area=data.expeditions and data.expeditions[data.activeExpeditionArea]
    if not area or not area.entityId then return {} end
    local result={'world:scene','player:'..id,'entity:'..area.entityId}
    if containerId then result[#result+1]='entity:'..containerId end
    return result
end
function Commands.install(authority,context)
    for _,name in ipairs({'expedition.survey','expedition.cache'}) do
        authority:register(name,function(data,id,args)
            local survey=name=='expedition.survey'
            if not P.fields(args,survey and {areaId=true,markerId=true} or {areaId=true,containerId=true})
                or not P.text(args.areaId,64) or not P.text(survey and args.markerId or args.containerId,64) then return nil,'invalid_args' end
            local actor=context.actorState(id); local own=Players.get(data,id)
            local area=Areas.current(data); local state=area and data.expeditions[area.id]
            if not actor or actor.screen~='game' or actor.scene~='expedition' or data.scene~='expedition'
                or not area or area.stop~=data.location or not state or args.areaId~=area.id or not own or own.health<=0
                or actor.traveling or actor.changingCar or actor.encounterActive or actor.activityBlocked or actor.movementReady==false
                or data.tacticalBattle or data.expeditionBattle or data.roamingEncounter or data.events.current or data.coop.journey
                or not point(actor.x) or not point(actor.y) or not Areas.isWalkable(data,area.id,actor.x,actor.y,true) then return nil,'assistance_unavailable' end
            local chest,record,spot
            if not survey then
                chest,record=Entities.find(data,args.containerId)
                if not chest or record.kind~='expeditionChest' or record.areaId~=area.id then return nil,'invalid_cache' end
            end
            for _,definition in ipairs(area.interactions or {}) do
                if survey and definition.kind=='survey' and definition.markerId==args.markerId
                    or not survey and definition.kind=='chest' and definition.chestId==record.key then spot=definition; break end
            end
            if not spot then return nil,survey and 'invalid_marker' or 'invalid_cache' end
            if not near(data,area,spot,actor) then return nil,'out_of_reach' end
            if spot.requires and not (state.gates and state.gates[spot.requires]) then return nil,'cache_sealed' end
            return {scopes=Commands.scopes(data,id,args.containerId),checkpoint=true,apply=function()
                if not survey then chest.opened=true; return {areaId=area.id,containerId=chest.entityId,opened=true} end
                local already=state.markers[spot.markerId]==true
                state.markers[spot.markerId]=true
                local gates=Areas.updateGates(data,area.id); local marked=0
                for _,marker in ipairs(area.completionRequiredMarkers or {}) do if state.markers[marker] then marked=marked+1 end end
                return {areaId=area.id,markerId=spot.markerId,already=already,marked=marked,
                    total=#(area.completionRequiredMarkers or {}),complete=gates.routeSurveyed==true}
            end}
        end)
    end
end
function Commands.message(result)
    if result.containerId then return 'Cache opened.' end
    return result.already and 'This cairn is already marked.' or result.complete and 'The basin route is fully surveyed.'
        or ('Cairn marked. '..result.marked..' of '..result.total..' charted.')
end
return Commands
