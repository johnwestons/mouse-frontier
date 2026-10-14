-- One host-owned patient session. Either actor can assist; story checks stay
-- on host interactions and the existing victory reward remains host-owned.
local P=require('game.net.protocol')
local Players=require('game.coop_players')
local Life=require('game.coop_last_stand_lifecycle')
local Leases=require('game.coop_leases')
local Model=require('game.first_aid')
local State=require('game.coop_last_stand_aid_state')
local Aid={}
local actions={acquire=true,inspect=true,press=true,move=true,release=true,choose=true,tick=true,pause=true,complete=true}
local pointers={press=true,move=true,release=true}
local function number(n) return type(n)=='number' and n==n and n>=-4096 and n<=4096 end
function Aid.resource(questId) return 'lastStand:'..questId..':aid' end
function Aid.scopes(data)
    local life=data.lastStand and data.lastStand.lifecycle; if not life then return {} end
    return {'world:scene','entity:'..life.entityId,'activity:'..Aid.resource(life.entityId),'story:events'}
end
local function facts(quest,lease,action,outcome)
    local session=lease.payload.session
    return {actorId=lease.actorId,questId=quest.lifecycle.entityId,revision=quest.lifecycle.revision,action=action,
        leaseId=lease.id,itemName='house medical supplies',phase=session.phase,ready=session.ready==true,
        dragging=session.dragging==true,pointer={x=session.pointer.x,y=session.pointer.y},outcome=outcome,
        expiresIn=outcome=='cancelled' and 0 or Leases.TIMEOUT,session=session}
end
function Aid.install(authority,context)
    authority:register('lastStand.aid',function(data,id,args,transaction)
        local action=args.action; local allowed={questId=true,revision=true,action=true}
        if action~='acquire' and action~='inspect' then allowed.leaseId=true end
        if pointers[action] then allowed.x=true; allowed.y=true end
        if action=='choose' then allowed.index=true end
        if not actions[action] or not P.fields(args,allowed) or not P.text(args.questId,32)
            or not P.integer(args.revision,1,Life.MAX)
            or allowed.leaseId and (not P.text(args.leaseId,32) or not args.leaseId:match('^l[1-9]%d*$'))
            or pointers[action] and (not number(args.x) or not number(args.y))
            or action=='choose' and not P.integer(args.index,1,6) then return nil,'invalid_args' end
        local quest=data.lastStand; local life=quest and quest.lifecycle
        local scene=context.lastStandScene and context.lastStandScene()
        local actor=context.actorState(id); local pose=Life.pose(data,id); local pause=action=='pause'
        if not life or not Life.validate(data) or not State.validate(data) or life.entityId~=args.questId or life.mode~='backyard'
            or quest.originStop~=data.location or data.scene~='stop' or not data.stopped or data.tacticalBattle or data.roamingEncounter or data.coop.journey
            or not scene or not scene.active or scene.questId~=life.entityId or scene.mode~=life.mode or scene.blocked
            or not actor or actor.screen~='game' or actor.scene~='stop' or actor.traveling or actor.changingCar
            or actor.activeActivity and actor.activeActivity~='lastStandAid'
            or not pause and (Players.forActor(data,id).health<=0 or id=='host' and (scene.personalPaused or scene.paused and not scene.treatmentLeaseId)
                or id~='host' and (actor.movementReady~=true or actor.modalDomain~=Life.key(data))) then return nil,'patient_unavailable' end
        if life.revision~=args.revision or scene.revision~=life.revision then return nil,'stale_phase' end
        if not pause and (not pose or (pose.x-750)^2+(pose.y-455)^2>65^2) then return nil,'patient_distance' end
        local resource=Aid.resource(life.entityId)
        if action=='inspect' or action=='acquire' and quest.woundedTreated then
            return {scopes=Aid.scopes(data),checkpoint=true,apply=function()
                if id=='host' then
                    quest.residentChecked=quest.victory or quest.residentChecked
                    quest.conversations=quest.conversations or {}; quest.conversations['help-wounded']=true
                end
                return {actorId=id,questId=life.entityId,revision=life.revision,action=action,inspected=true,treated=quest.woundedTreated==true}
            end}
        end
        if action=='acquire' then
            if actor.activeActivity then return nil,'actor_busy' end
            return {scopes=Aid.scopes(data),checkpoint=true,apply=function()
                local progress=State.ensure(data)
                local session=Model.new({progress=progress,location=data.location,itemName='house medical supplies'})
                session.ready=State.ready(progress)
                local lease,reason=Leases.acquire(transaction.state,resource,id,transaction.generation,data.coop.sceneEpoch,transaction.now,
                    {kind='lastStandAid',modalDomain=Life.key(data),session=session,lastUpdate=transaction.now})
                if not lease then return nil,reason end
                if id=='host' then
                    quest.residentChecked=quest.victory or quest.residentChecked
                    quest.conversations=quest.conversations or {}; quest.conversations['help-wounded']=true
                end
                return facts(quest,lease,action)
            end}
        end
        local lease,reason=Leases.find(transaction.state,args.leaseId,id,transaction.generation,data.coop.sceneEpoch,transaction.now)
        if not lease then return nil,reason end
        local payload=lease.payload
        if payload.kind~='lastStandAid' or lease.resource~=resource or payload.modalDomain~=Life.key(data) then return nil,'wrong_activity' end
        if id=='host' and not pause and scene.treatmentLeaseId~=lease.id then return nil,'patient_unavailable' end
        if quest.woundedTreated and not pause then return nil,'patient_treated' end
        local cancel=action=='press' and args.x>=350 and args.x<=610 and args.y>=608 and args.y<=650
        local operation={scopes=Aid.scopes(data),checkpoint=pause or cancel or action=='complete'}
        operation.apply=function()
            local session=payload.session; session.progress=State.ensure(data)
            local previousPhase=session.phase
            if action=='complete' then
                if not session.ready or not State.ready(session.progress) then return nil,'treatment_incomplete' end
                local before=quest.positionIntegrity or 100
                quest.woundedTreated=true; quest.positionIntegrity=math.min(100,before+12)
                Leases.release(transaction.state,lease)
                return {actorId=id,questId=life.entityId,revision=life.revision,action=action,completed=true,
                    integrityBefore=before,integrity=quest.positionIntegrity}
            end
            local outcome
            if not pause and not session.ready then
                outcome=Model.update(session,transaction.now-payload.lastUpdate)
                if action=='press' then outcome=Model.mousepressed(session,args.x,args.y) or outcome
                elseif action=='move' then outcome=Model.mousemoved(session,args.x,args.y) or outcome
                elseif action=='release' then Model.mousereleased(session,args.x,args.y)
                elseif action=='choose' then outcome=Model.choose(session,args.index) or outcome end
            end
            payload.lastUpdate=transaction.now
            if outcome=='complete' then session.ready=true end
            if session.phase~=previousPhase or outcome=='complete' then operation.checkpoint=true end
            if pause or outcome=='cancelled' then
                session.dragging=false; session.previousPointer=nil; Leases.release(transaction.state,lease); outcome='cancelled'
            else lease.expiresAt=transaction.now+Leases.TIMEOUT end
            return facts(quest,lease,action,outcome)
        end
        return operation
    end)
end
return Aid
