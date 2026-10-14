local Players=require("game.coop_players")
local Leases=require("game.coop_leases")
local Model=require("game.first_aid")
local Help=require("game.stop_help_progression")
local Quests=require("game.help_quest_session")
local Access=require('game.coop_aid_access')
local Contract=require('game.coop_item_contract')
local P=require('game.net.protocol')
local Commands={}

local function finite(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end
local function fields(args,allowed)
    for key in pairs(args) do if not allowed[key] then return false end end
    return true
end

function Commands.install(authority,context)
    local function patient(data,actorId,targetId,npc)
        local actor=Players.forActor(data,actorId)
        local found,reason=Access.patient(actor,context.actorState(actorId),targetId,npc)
        if found then found.actor=actor end
        return found,reason
    end

    local function facts(lease,outcome)
        local session=lease.payload.session
        return {ok=true,leaseId=lease.id,questId=session.helpQuestId,itemName=session.itemName,
            phase=session.phase,ready=session.ready==true,dragging=session.dragging==true,
            pointer={x=session.pointer.x,y=session.pointer.y},outcome=outcome,expiresIn=outcome=='cancelled' and 0 or Leases.TIMEOUT,
            session=session}
    end

    authority:register("firstAid.acquire",function(data,actorId,args,transaction)
        if not fields(args,{targetId=true,npc=true,source=true,selected=true}) then return nil,"invalid_args" end
        local target,reason=patient(data,actorId,args.targetId,args.npc); if not target then return nil,reason end
        if Leases.npcBusy(transaction.state,args.targetId,args.npc) then return nil,'activity_busy' end
        local slot,name=Help.medicalItem(target.actor,context.catalog)
        if args.source~=nil then
            if not P.fields(args.source,{kind=true,index=true}) or args.source.kind~='inventory'
                or not P.integer(args.source.index,1,target.actor.inventoryCapacity) then return nil,'invalid_args' end
            slot=args.source.index; name=target.actor.inventory[slot]
            local effect=name and context.catalog.itemEffects[name]
            if not effect or not effect.health or not Contract.matches(args.selected,target.actor,nil,args.source) then return nil,'medical_supply' end
        end
        if actorId~='host' and (args.source==nil or args.selected==nil) then return nil,'item_selection_required' end
        if not slot then return nil,"medical_supply" end
        local resource="firstAid:"..target.quest.id
        local selected=Contract.selection(target.actor,nil,{kind='inventory',index=slot})
        return {scopes={"activity:"..resource,"quest:"..target.quest.id,'player:'..actorId},apply=function()
            local session=Model.new({npc=args.npc,location=data.location,itemSlot=slot,itemName=name,
                helpQuestId=target.quest.id,progress=target.quest.progress})
            session.ready=session.phase==6 and session.progress.gauzePlaced and session.progress.wrapPasses>=Model.requiredWrapPasses
            local lease,errorMessage=Leases.acquire(transaction.state,resource,actorId,transaction.generation,
                data.coop.sceneEpoch,transaction.now,{kind="firstAid",targetId=args.targetId,npc=args.npc,
                    session=session,lastUpdate=transaction.now,selected=selected,
                    supplyRevision=(data.coop.revisions['player:'..actorId] or 0)+1})
            if not lease then return nil,errorMessage end
            Quests.activate(data,target.quest.id,"Find the small cut, then complete all five treatment steps.")
            return facts(lease)
        end}
    end)

    for _,command in ipairs({"firstAid.step","firstAid.complete"}) do
        authority:register(command,function(data,actorId,args,transaction)
            local allowed=command=="firstAid.complete" and {leaseId=true} or {leaseId=true,action=true,x=true,y=true,index=true}
            if not fields(args,allowed) or type(args.leaseId)~="string" then return nil,"invalid_args" end
            if command=="firstAid.step" then
                local action=args.action
                local pointer=action=="press" or action=="move" or action=="release"
                if pointer then
                    if args.index~=nil or not finite(args.x) or not finite(args.y) or math.abs(args.x)>4096 or math.abs(args.y)>4096 then return nil,"invalid_args" end
                elseif action=="choose" then
                    if args.x~=nil or args.y~=nil or not finite(args.index) or args.index%1~=0 or args.index<1 or args.index>Model.phaseCount then return nil,"invalid_args" end
                elseif action=="tick" or action=="pause" then
                    if args.x~=nil or args.y~=nil or args.index~=nil then return nil,"invalid_args" end
                else return nil,"invalid_args" end
            end
            local lease,reason=Leases.find(transaction.state,args.leaseId,actorId,transaction.generation,data.coop.sceneEpoch,transaction.now)
            if not lease then return nil,reason end
            local payload=lease.payload
            if payload.kind~="firstAid" then return nil,"wrong_activity" end
            local target,unavailable
            if command=='firstAid.step' and args.action=='pause' then
                target,unavailable=Access.patient(Players.forActor(data,actorId),context.actorState(actorId),payload.targetId,payload.npc,true)
                if target then target.actor=Players.forActor(data,actorId) end
            else target,unavailable=patient(data,actorId,payload.targetId,payload.npc) end
            if not target then return nil,unavailable end
            if payload.session.helpQuestId~=target.quest.id or payload.session.location~=data.location then return nil,"quest_unavailable" end
            local scopes={"activity:"..lease.resource,"quest:"..target.quest.id}
            if command=="firstAid.complete" then
                scopes[#scopes+1]="player:"..actorId; scopes[#scopes+1]="relationships"; scopes[#scopes+1]="entity:"..payload.targetId
            end
            if args.action~='pause' and ((data.coop.revisions['player:'..actorId] or 0)~=payload.supplyRevision
                or not Contract.matches(payload.selected,target.actor,nil,{kind='inventory',index=payload.session.itemSlot})) then return nil,'medical_supply_changed' end
            return {scopes=scopes,checkpoint=command=='firstAid.step' and args.action=='pause',apply=function()
                local session=payload.session
                -- Activity state and campaign state are copied separately for
                -- rollback. Rebind only this patient's persisted checkpoint.
                session.progress=target.quest.progress
                if command=="firstAid.complete" then
                    if not session.ready then return nil,"treatment_incomplete" end
                    local result=Help.completeAid(target.actor,target.request,session,payload.npc,data.location)
                    if not result.completed then return nil,"medical_supply" end
                    Leases.release(transaction.state,lease)
                    return {ok=true,completed=true,gained=result.gained,total=result.total,item=result.item}
                end
                local outcome
                if not session.ready then
                    -- Pointer position and elapsed time belong to the host;
                    -- requests carry neither duration nor treatment progress.
                    outcome=Model.update(session,transaction.now-payload.lastUpdate)
                    if args.action=="press" then outcome=Model.mousepressed(session,args.x,args.y) or outcome
                    elseif args.action=="move" then outcome=Model.mousemoved(session,args.x,args.y) or outcome
                    elseif args.action=="release" then Model.mousereleased(session,args.x,args.y)
                    elseif args.action=="choose" then outcome=Model.choose(session,args.index) or outcome end
                end
                payload.lastUpdate=transaction.now
                if outcome=="complete" then session.ready=true end
                target.quest.stage=session.phase
                if args.action=="pause" or outcome=="cancelled" then
                    Quests.pause(data,target.quest.id,"Return to the wounded critter to continue treatment.")
                    session.dragging=false; session.previousPointer=nil
                    Leases.release(transaction.state,lease); outcome="cancelled"
                else lease.expiresAt=transaction.now+Leases.TIMEOUT end
                return facts(lease,outcome)
            end}
        end)
    end
end

return Commands
