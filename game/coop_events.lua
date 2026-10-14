-- Saved host event identity, detached choices and explicit continuation.
local Events=require('game.events')
local Balance=require('game.event_balance')
local Combat=require('game.combat_balance')
local Train=require('game.train_upgrade_balance')
local Players=require('game.coop_players')
local Party=require('game.party_scene')
local Random=require('game.coop_random')
local P=require('game.net.protocol')
local Commands={}
local Entities=require('game.coop_entities')
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<100000 end
local function positions(data)
    local actors={}
    for _,id in ipairs({'host','companion'}) do
        local actor=Players.get(data,id)
        if actor then
            if not finite(actor.playerX) or not finite(actor.playerY) then return nil end
            actors[id]={x=actor.playerX,y=actor.playerY,carIndex=actor.activeCar,facing=actor.playerFacing or 1}
        end
    end
    return actors
end
local function active(data,id)
    local current=data.events and data.events.current
    if current and current.id==id and current.location==data.location and current.scene==data.scene
        and current.sceneEpoch==data.coop.sceneEpoch then return current end
end
local function validOutcome(event,index,result,location)
    if not P.fields(result,{encounter=true,notes=true,clue=true,summary=true,trainAmbush=true})
        or type(result.notes)~='table' or #result.notes>3 or result.clue~=event.clue
        or result.trainAmbush~=nil and type(result.trainAmbush)~='boolean' then return false end
    local choice=event.choices[index]
    for key,note in pairs(result.notes) do
        if not P.integer(key,1,#result.notes) or not P.text(note,160) then return false end
        if not note:match('^found [%w%-]+$') and not note:match('^lost [%w%-]+$')
            and not note:match('^received %d+ [%w%-]+$') then return false end
    end
    if choice.trainAmbush then
        if result.encounter~=nil or #result.notes>0 or result.trainAmbush~=(choice.trainAmbush=='fight') then return false end
        if choice.trainAmbush=='fight' then return result.summary==nil end
        if choice.trainAmbush=='pay' then return result.summary=='Paid '..require('game.train_ambush_rules').bribe..' scrap. The pickup falls behind.' end
        return P.text(result.summary,160) and result.summary:match('^The pickup passes%. Spent %d food and %d water%. Train condition lost: %d+%.$')~=nil
    end
    local summary=choice.hint or 'The journey continues.'
    if #result.notes>0 then
        local readable={}
        for _,note in ipairs(result.notes) do
            readable[#readable+1]=note:gsub('%-',' '):gsub("(%a)([%w']*)",function(a,b) return a:upper()..b end)
        end
        summary=summary..'  '..table.concat(readable,', ')..'.'
    end
    if result.summary~=summary or result.trainAmbush~=nil then return false end
    local encounter=result.encounter
    if not choice.battle then return encounter==nil end
    if not P.fields(encounter,{rolled=true,hasMob=true,resolved=true,tier=true,mobFiles=true,eventBattle=true,eventReward=true,
        eventRewardQuality=true,defenseBattle=true,defenseTitle=true,temporaryAllies=true})
        or encounter.rolled~=true or encounter.hasMob~=true or encounter.resolved~=false or encounter.tier~=Combat.tierFor(location)
        or encounter.eventBattle~=true or encounter.eventReward~=true or encounter.eventRewardQuality~=(choice.rewardQuality or 2)
        or encounter.defenseBattle~=choice.defense or encounter.defenseTitle~=event.title
        or type(encounter.mobFiles)~='table' or not P.integer(#encounter.mobFiles,1,5)
        or choice.count and #encounter.mobFiles~=choice.count then return false end
    local known={}; for _,file in ipairs(require('game.catalog').mobTiers[encounter.tier] or {}) do known[file]=true end
    for key,file in pairs(encounter.mobFiles) do if not P.integer(key,1,#encounter.mobFiles) or not known[file] then return false end end
    if choice.allies then
        if type(encounter.temporaryAllies)~='table' or #encounter.temporaryAllies>choice.allies then return false end
        for key,file in pairs(encounter.temporaryAllies) do if not P.integer(key,1,#encounter.temporaryAllies) or not P.text(file,128) then return false end end
    elseif encounter.temporaryAllies~=nil then return false end
    return true
end
function Commands.validateCurrent(data)
    local current=data.events and data.events.current
    if current==nil then return true end
    if not P.fields(current,{id=true,location=true,scene=true,sceneEpoch=true,phase=true,index=true,outcome=true})
        or not P.text(current.id,64) or not P.integer(current.location,1,49) or current.location~=data.location
        or current.scene~=data.scene or current.scene~='train' or not data.coop or current.sceneEpoch~=data.coop.sceneEpoch then return false end
    local event=Events.findById(current.id); if not event then return false end
    local receipt=data.events[tostring(current.location)]
    if current.phase=='prompt' then return current.index==nil and current.outcome==nil and receipt==nil end
    return current.phase=='chosen' and P.integer(current.index,1,#event.choices) and type(receipt)=='table'
        and receipt.id==current.id and receipt.choice==current.index and validOutcome(event,current.index,current.outcome,current.location)
end
function Commands.readAlong(data)
    local current=data.events and data.events.current
    if not current or not Commands.validateCurrent(data) then return nil end
    local event=Events.findById(current.id)
    return {id=event.id,title=event.title,text=event.text,category=event.category,waiting=current.phase=='prompt',
        answer=current.index and event.choices[current.index].label,notice=current.outcome and (current.outcome.clue or current.outcome.summary)}
end
function Commands.restore(runtime)
    local data=runtime.saveData; local current=data and data.events and data.events.current
    if current and Commands.validateCurrent(data) then
        runtime.randomEvent=Events.findById(current.id)
        runtime.eventOutcome=current.phase=='chosen' and current.outcome or nil
        return true
    end
    return false
end
function Commands.install(authority,context)
    local function state(data,screen)
        local host=context.actorState('host')
        if not host or host.screen~=screen or host.scene~=data.scene or host.traveling or host.changingCar
            or host.encounterActive or host.activityBlocked or data.scene~='train' or data.coop.journey
            or data.location>=50 or data.health<=0 then return nil end
        return host
    end
    local function scopes(data)
        local result={'party','story:events','world:scene','world:rewardDelivery','resources','rng','player:host',
            'world:encounters','world:trainAmbush','world:maintenance'}
        if data.players.companion then result[#result+1]='player:companion' end
        for _,item in ipairs(data.droppedItems or {}) do
            if item.name=='mailbox-reward' and item.scene=='train' then result[#result+1]='entity:'..item.entityId; break end
        end
        return result
    end
    authority:register('event.begin',function(data,id,args,t)
        if not P.fields(args,{mode=true,id=true}) or (args.mode~='required' and args.mode~='random' and args.mode~='named')
            or args.mode=='named' and not Events.findById(args.id) or args.mode~='named' and args.id~=nil then return nil,'invalid_args' end
        if not state(data,'game') or not positions(data) then return nil,'event_unavailable' end
        if data.events.current or data.events[tostring(data.location)] then return nil,'event_already_played' end
        return {scopes=scopes(data),apply=function()
            local rng=Random.generator(data,t.randomSeed)
            local event=args.mode=='required' and Events.required(data,data.location,rng)
                or args.mode=='named' and Events.findById(args.id) or args.mode=='random' and Events.random(data,Balance,rng)
            if not event then return nil,'event_unavailable' end
            local result,reason=Party.commit(data,t,positions(data),'event'); if not result then return nil,reason end
            data.events.current={id=event.id,location=data.location,scene=data.scene,sceneEpoch=data.coop.sceneEpoch,phase='prompt'}
            result.eventId=event.id; return result
        end}
    end)
    authority:register('event.choose',function(data,id,args,t)
        if not P.fields(args,{id=true,index=true}) or not P.text(args.id,64) or not P.integer(args.index,1,3) then return nil,'invalid_args' end
        local current=active(data,args.id); local event=Events.findById(args.id)
        if not current or current.phase~='prompt' or not state(data,'event') then return nil,'event_unavailable' end
        if not Events.canChoose(data,event.choices[args.index],context.catalog) then return nil,'choice_unavailable' end
        return {scopes=scopes(data),apply=function()
            local outcome=Events.resolve(data,context.catalog,event,args.index,Combat,Train,Random.generator(data,t.randomSeed))
            if outcome.blocked then return nil,'choice_unavailable' end
            current.phase='chosen'; current.index=args.index; current.outcome=outcome
            return {ok=true,eventId=event.id,index=args.index,outcome=outcome}
        end}
    end)
    authority:register('event.continue',function(data,id,args,t)
        if not P.fields(args,{id=true}) or not P.text(args.id,64) then return nil,'invalid_args' end
        local current=active(data,args.id)
        if not current or current.phase~='chosen' or not state(data,'event') or not positions(data) then return nil,'event_unavailable' end
        return {scopes=scopes(data),apply=function()
            local outcome=current.outcome
            if outcome.encounter then data.encounters[tostring(data.location)]=outcome.encounter end
            data.events.current=nil
            local ready,reason=Entities.ensure(data); if not ready then return nil,reason end
            local result,reason=Party.commit(data,t,positions(data),'game'); if not result then return nil,reason end
            result.eventId=current.id; result.outcome=outcome; return result
        end}
    end)
end
return Commands
