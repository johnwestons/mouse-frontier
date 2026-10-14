-- The host owns the final campaign choice; guests receive a passive summary.
local Finale=require('game.finale_progression')
local Players=require('game.coop_players')
local Help=require('game.stop_help_progression')
local Maintenance=require('game.maintenance_rules')
local P=require('game.net.protocol')
local Commands={}
function Commands.validate(data)
    local state=data.finale
    if state==nil then return true end
    return P.fields(state,{choice=true,completed=true})
        and (state.choice==nil or Finale.choice(state.choice)~=nil)
        and (state.completed==nil or state.completed==(state.choice~=nil))
end
function Commands.available(data)
    data=Players.campaignOf(data)
    return data and data.location==50 and data.scene=='train' and not (data.coop and data.coop.journey)
        and not (data.events and data.events.current) or false
end
function Commands.summary(data)
    data=Players.campaignOf(data)
    local host=data.players and data.players.host or data
    -- Existing evaluators normalize their input. Give them private scratch
    -- tables, so neither host drawing nor guest inspection writes a campaign.
    local scratch={goodwill=data.goodwill,helpHistory=data.helpHistory,eventProgress=data.eventProgress,
        trainCars=data.trainCars,stats=host.stats,maintenance={condition=data.maintenance and data.maintenance.condition},
        finale={choice=data.finale and data.finale.choice}}
    local result=Finale.evaluate(scratch,Help,{condition=function(value) return Maintenance.ensure(value).condition end})
    if result.choice then
        result.choice={id=result.choice.id,title=result.choice.title,description=result.choice.description}
    end
    return result
end
function Commands.readAlong(data)
    if not Commands.available(data) or not Commands.validate(data) then return nil end
    return Commands.summary(data)
end
function Commands.install(authority,context)
    authority:register('finale.choose',function(data,id,args)
        if not P.fields(args,{id=true}) or not Finale.choice(args.id) then return nil,'invalid_args' end
        local host=context.actorState('host')
        if not host or host.screen~='ending' or host.scene~=data.scene or host.traveling or host.changingCar
            or host.encounterActive or host.activityBlocked or not Commands.available(data) then return nil,'finale_unavailable' end
        if data.finale and data.finale.choice then return nil,'finale_already_chosen' end
        return {scopes={'party','world:scene','story:finale'},apply=function()
            if not Finale.choose(data,args.id) then return nil,'choice_unavailable' end
            return {ok=true,choice=args.id}
        end}
    end)
end
return Commands
