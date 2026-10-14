-- Staged render QA only: detached, unslotted, nonpersistent offline campaign.
-- Production command handlers, reach checks and permissions remain installed.
local Areas=require('game.expedition_areas')
local State=require('game.tactical_battle_state')
local Fixture={IDENTITY='mouse-frontier-expedition-integration-qa'}

function Fixture.assertIsolated(runtime,session,identity)
    assert(identity()==Fixture.IDENTITY,'preview save identity changed')
    assert(runtime.selectedSlot==nil and session.selectedSlot==nil,'preview must remain unslotted')
    assert(session.networkMode=='offline' and session.localPlayerId=='host','preview must remain ordinary offline play')
end

function Fixture.commands(original,context,identity)
    local function guard() Fixture.assertIsolated(context.runtime,context.session,identity) end
    guard()
    local detached={}; for key,value in pairs(context) do detached[key]=value end
    detached.checkpoint=nil -- Real Authority option; no invented durable receipt.
    local commands=original(detached)
    local submit,authority=commands.submit,commands.authority
    commands.submit=function(...)
        guard()
        local reply=submit(...)
        assert(not reply.durable and not reply.savePending,'nonpersistent preview produced a save receipt')
        return reply
    end
    commands.authority=function(...) guard(); return authority(...) end
    return commands
end

function Fixture.installSaveTripwires(save)
    for _,name in ipairs({'write','schedule','remove'}) do
        save[name]=function() error('campaign save operation forbidden in isolated preview: '..name) end
    end
end

function Fixture.gate(data,target,spawn)
    local interactions
    if data.scene=='stop' then interactions={assert(Areas.entrance(data.location),'missing stop entrance')}
    else interactions=assert(Areas.current(data),'missing current expedition').interactions end
    for _,gate in ipairs(interactions) do
        if gate.kind=='enterArea' and gate.target==target and gate.spawn==spawn then return gate end
    end
    error('no authored gate from '..tostring(data.activeExpeditionArea or data.scene)..' to '..tostring(target)..':'..tostring(spawn))
end

function Fixture.enter(runtime,world,position,target,spawn)
    local gate=Fixture.gate(runtime.saveData,target,spawn)
    position(gate.x,gate.y)
    local selected=world.currentExpeditionInteraction()
    assert(selected and selected.action=='enterArea' and selected.id==gate.id
        and selected.targetArea==target and selected.spawn==spawn,'authored gate is not currently reachable/selected')
    return world.activateExpeditionInteraction(selected)
end

function Fixture.resolveStagedBattle(runtime,commands,catalog,outcome)
    assert(outcome=='win' or outcome=='loss','invalid staged result')
    local data=runtime.saveData
    local battle=assert(State.restore(data,catalog),'missing canonical tactical battle')
    assert(not battle.finished,'battle already finished')
    -- Fixture damage prepares a result screenshot; this is not a natural fight.
    -- Edit the canonical board, then let an actual permitted host action settle
    -- rewards/enemy health/result through the production transaction.
    local survivor=outcome=='win' and 'ally' or 'enemy'
    local active
    for i,unit in ipairs(battle.units) do
        if unit.team~=survivor then unit.hp=0
        elseif not active and unit.hp>0 then active=i end
        unit.actionTimer=0; unit.hitTimer=0; unit.moveAnim=nil
    end
    battle.active=assert(active,'staged result has no living active unit')
    battle.intro=nil; battle.attackTimer=0; battle.enemyDelay=0; battle.projectile=nil
    runtime.battle=battle
    local state=data.tacticalBattle
    local reply=commands.submit(outcome=='win' and 'battle.endTurn' or 'battle.enemyTurn',
        {encounterId=state.encounterId,turnRevision=state.revision,unitId=battle.units[battle.active].id})
    assert(reply.ok,'staged battle result rejected: '..tostring(reply.reason))
    runtime.battle=assert(State.restore(data,catalog))
    assert(runtime.battle.finished==outcome,'authoritative battle result did not settle')
    return reply
end

return Fixture
