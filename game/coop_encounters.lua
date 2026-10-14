-- Stop encounters are rolled once by the host and checkpointed before entry.
local Events=require('game.events')
local EventBalance=require('game.event_balance')
local Combat=require('game.combat_balance')
local Random=require('game.coop_random')
local Entities=require('game.coop_entities')
local P=require('game.net.protocol')
local Commands={}
function Commands.install(authority,context)
    authority:register('encounter.roll',function(data,id,args,t)
        if not P.fields(args,{}) then return nil,'invalid_args' end
        local host=context.actorState('host')
        if not host or host.screen~='game' or host.scene~='train' or data.scene~='train'
            or host.traveling or host.changingCar or host.encounterActive or host.activityBlocked
            or not P.integer(data.location,1,49) or data.health<=0
            or data.coop.journey or data.events.current then return nil,'encounter_unavailable' end
        local key=tostring(data.location); local existing=data.encounters[key]
        local scopes={'party','world:scene','world:encounters','story:events','rng'}
        if existing then scopes[#scopes+1]='entity:'..existing.entityId end
        return {scopes=scopes,apply=function()
            if existing then return {ok=true,existing=true,stop=data.location,encounter=existing} end
            local rng=Random.generator(data,t.randomSeed); local random=Random.range(rng)
            -- Required chapters precede the ordinary encounter, including when
            -- a forged/local caller bypasses JourneyRules' event routing.
            if not data.events[key] and Events.required(data,data.location,rng) then return nil,'required_event' end
            local encounter
            if data.forceEventId and not data.events[key] then
                if not Events.findById(data.forceEventId) then return nil,'invalid_forced_event' end
                encounter={rolled=true,hasMob=false,resolved=true,testEvent=true}
            else
                local boss=data.location==15 or data.location==35 or data.location==47
                local mob=boss or random()<EventBalance.encounterChance(data.location)
                local tier=Combat.tierFor(data.location)
                encounter={rolled=true,hasMob=mob,resolved=not mob,tier=tier,boss=boss}
                local pool=context.catalog.mobTiers[tier]
                if mob and #pool>0 then
                    encounter.mobFiles={}
                    for i=1,Combat.mobCount(tier,data.location,random()) do encounter.mobFiles[i]=pool[random(#pool)] end
                    encounter.mobFile=encounter.mobFiles[1]
                end
            end
            data.encounters[key]=encounter
            local ready,reason=Entities.ensure(data); if not ready then return nil,reason end
            return {ok=true,stop=data.location,encounter=encounter}
        end}
    end)
end
return Commands
