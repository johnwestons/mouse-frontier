-- Host decisions use detached campaign transactions and durable receipts.
local P=require('game.net.protocol')
local Rules=require('game.train_ambush_rules')
local Players=require('game.coop_players')
local Shooting=require('game.first_person_shooting')
local Party=require('game.party_scene')
local Settlements=require('game.settlements')
local NPCs=require('game.scene_npcs')
local Items=require('game.item_instances')
local Random=require('game.coop_random')
local Commands={}
local outcomes={disabled=true,crew=true,escaped=true,overrun=true,withdrawn=true}
function Commands.scopes(data)
    local state=data.trainAmbush
    local result={'world:scene','world:trainAmbush','resources','world:maintenance','story:events','party','relationships','rng','player:host'}
    if state and state.entityId then result[#result+1]='entity:'..state.entityId end
    if data.players.companion then result[#result+1]='player:companion' end
    return result
end
function Commands.install(authority,context)
    for _,name in ipairs({'ambush.start','ambush.withdraw','ambush.continue','ambush.retry'}) do
        authority:register(name,function(data,id,args,transaction)
            if not P.fields(args,{encounterId=true}) or not P.text(args.encounterId,32) then return nil,'invalid_args' end
            if id~='host' then return nil,'host_only' end
            local state=data.trainAmbush; local actor=context.actorState(id)
            local ready=context.ambushState and context.ambushState(id)
            if not state or state.entityId~=args.encounterId or not state.active or state.location~=data.location
                or data.scene~='train' or not actor or actor.screen~='game' or actor.scene~='train'
                or actor.traveling or actor.changingCar or actor.activeActivity or data.tacticalBattle
                or data.roamingEncounter or data.coop.journey or require('game.coop_last_stand_lifecycle').active(data)
                or name~='ambush.start' and (not ready or not ready.active or ready.paused or ready.encounterId~=state.entityId) then
                return nil,'ambush_unavailable'
            end
            if name=='ambush.retry' then return nil,'retry_unavailable' end -- No retry rule/control exists in the original ambush.
            if name=='ambush.start' then
                -- Authored event.choose creates the initial state. An existing
                -- saved active state is also legitimate restoration; this API
                -- cannot fabricate an encounter or bypass the event decision.
                if state.phase~='approach' and state.phase~='combat' and state.phase~='depart' and state.phase~='result' then return nil,'ambush_unavailable' end
            elseif name=='ambush.withdraw' then
                if state.outcome or state.phase~='approach' and state.phase~='combat' then return nil,'withdraw_unavailable' end
            elseif state.phase~='result' or not outcomes[state.outcome] then return nil,'result_unavailable' end
            return {scopes=Commands.scopes(data),checkpoint=true,apply=function()
                if name=='ambush.start' then
                    Rules.start(data)
                    Shooting.new(Players.forActor(data,'host'),context.catalog,state,960,720)
                    return {encounterId=state.entityId,phase=state.phase,outcome=state.outcome,reward=state.reward}
                elseif name=='ambush.withdraw' then
                    if not Rules.withdraw(data,state) then return nil,'withdraw_unavailable' end
                    return {encounterId=state.entityId,phase=state.phase,outcome=state.outcome,reward=state.reward}
                end
                state.active=false; data.scene='stop'; data.activeHouseDoor=nil; data.activeExpeditionArea=nil
                local x,y=Settlements.trainPoint(data.location)
                local actors,why=Party.place(data,function() return x,y end,
                    function(px,py) return Settlements.clamp(px,py,data.location) end)
                if not actors then return nil,why end
                NPCs.prepare(data,context.catalog,Random.generator(data,transaction.randomSeed))
                if Items.enabled(data) and not Items.ensure(data) then return nil,'invalid_items' end
                local result,why=Party.commit(data,transaction,actors)
                if not result then return nil,why end
                result.encounterId=state.entityId; result.outcome=state.outcome; result.reward=state.reward
                return result
            end}
        end)
    end
end
return Commands
