-- Local host administration crosses the same checked-save barrier as gameplay.
-- Callers retain newly generated raw credentials outside command arguments and
-- receipts, publishing them only after a durable result/retry checkpoint.
local P=require('game.net.protocol')
local Crypto=require('game.net.crypto')
local Players=require('game.coop_players')
local Commands={}
function Commands.install(authority,context)
    assert(type(context)=='table' and type(context.placeCompanion)=='function','companion spawn resolver required')
    local function register(name,prepare,connected)
        authority:register(name,function(data,actorId,args,transaction)
            if not connected and authority.bindings.companion then return nil,'companion_connected' end
            if not authority.checkpoint then return nil,'checkpoint_required' end
            return prepare(data,args,transaction)
        end)
    end
    register('session.host',function(data,args)
        if not P.fields(args,{campaignId=true}) or not Crypto.isHex(args.campaignId,32) then return nil,'invalid_identity' end
        if data.coop.network then return nil,'campaign_identity_exists' end
        return {scopes={'session'},apply=function()
            data.coop.network={version=1,campaignId=args.campaignId,bindingVersion=0}
            return {campaignId=args.campaignId}
        end}
    end)
    local function binding(data,args,enroll)
        local allowed={credentialHash=true,companionId=true}
        if enroll then allowed.character=true end
        local network=data.coop.network
        if not network then return nil,'campaign_identity_required' end
        if not P.fields(args,allowed) or not Crypto.isHex(args.credentialHash,64)
            or not Crypto.isHex(args.companionId,32) then return nil,'invalid_binding' end
        if network.bindingVersion>=2147483647 then return nil,'binding_exhausted' end
        if network.companionId and network.companionId~=args.companionId then return nil,'companion_identity_mismatch' end
        if not enroll and not data.players.companion then return nil,'companion_missing' end
        if network.credentialHash==args.credentialHash then return nil,'credential_unchanged' end
        local scopes={'session','player:companion'}
        local modal=require('game.coop_last_stand_lifecycle').active(data)
        if modal then scopes[#scopes+1]='entity:'..modal.entityId end
        if data.tacticalBattle then
            if data.tacticalBattle.revision>=2147483647 then return nil,'turn_revision_exhausted' end
            scopes[#scopes+1]='combat:tactical'
        end
        return {scopes=scopes,apply=function()
            if enroll then
                local player,reason=Players.enroll(data,'host',args.character,context.catalog,context.allowedCharacters)
                if not player then return nil,reason end
                local placed,spawnError=context.placeCompanion(data)
                if placed~=true then return nil,spawnError or 'spawn_unavailable' end
            end
            require('game.tactical_battle_state').queueCompanion(data)
            network.companionId=args.companionId; network.credentialHash=args.credentialHash
            network.bindingVersion=network.bindingVersion+1
            return {campaignId=network.campaignId,companionId=network.companionId,bindingVersion=network.bindingVersion}
        end}
    end
    register('session.enroll',function(data,args) return binding(data,args,true) end)
    register('session.rebind',function(data,args) return binding(data,args,false) end)

    local function managementState(data)
        if type(context.managementState)~='function'then return nil,'management_unavailable' end
        local ok,state=pcall(context.managementState)
        if not ok or type(state)~='table' or (state.screen~='game' and state.screen~='battle' and state.screen~='ending')
            or state.scene~=data.scene or state.saving~=false or state.pendingAdmission~=false then
            return nil,'management_unavailable'
        end
        return state
    end
    local function managementBinding(data,args,replacement)
        local network=data.coop.network
        if not network or not data.players.companion then return nil,'companion_missing' end
        if not Crypto.isHex(args.credentialHash,64) or args.credentialHash==network.credentialHash
            or not Crypto.isHex(args.companionId,32) then return nil,'invalid_binding' end
        if network.bindingVersion>=2147483647 then return nil,'binding_exhausted' end
        if replacement then
            if args.previousCompanionId~=network.companionId then return nil,'companion_identity_mismatch' end
            if args.companionId==network.companionId then return nil,'companion_identity_unchanged' end
        elseif args.companionId~=network.companionId then return nil,'companion_identity_mismatch'end
        return network
    end
    register('session.replace',function(data,args,transaction)
        if not P.fields(args,{character=true,previousCompanionId=true,companionId=true,credentialHash=true}) then return nil,'invalid_args' end
        local state,reason=managementState(data);if not state then return nil,reason end
        local active=require('game.coop_last_stand_lifecycle').active(data)
        local range=data.rangeSessions and data.rangeSessions.companion
        if state.screen~='game' or state.scene~='train' or data.stopped~=true or data.coop.journey
            or state.traveling~=false or state.encounterActive~=false or state.activityBlocked~=false
            or state.changingCar~=false or data.tacticalBattle or data.roamingEncounter or active
            or data.trainAmbush and data.trainAmbush.active or data.events and data.events.current
            or range and range.phase=='play' or next(transaction.state.resources)~=nil
            or transaction.state.positionOccupancy and next(transaction.state.positionOccupancy.windows)~=nil then
            return nil,'replacement_unavailable'
        end
        local network,bindingError=managementBinding(data,args,true);if not network then return nil,bindingError end
        if not P.text(args.character,128) or not context.allowedCharacters or context.allowedCharacters[args.character]~=true then return nil,'invalid_character' end
        if data.players.companion.character==args.character then return nil,'character_unchanged' end
        return {scopes={'session','player:companion'},apply=function()
            local player,replaceError=Players.replace(data,'host',args.character,context.catalog,context.allowedCharacters)
            if not player then return nil,replaceError end
            network.companionId=args.companionId;network.credentialHash=args.credentialHash
            network.bindingVersion=network.bindingVersion+1
            transaction.state.travelRequests=nil
            return {management='replace',character=player.character,campaignId=network.campaignId,
                companionId=network.companionId,bindingVersion=network.bindingVersion}
        end}
    end)
    register('session.kick',function(data,args,transaction)
        if not P.fields(args,{generation=true,companionId=true,credentialHash=true})
            or not P.integer(args.generation,1,2147483647) then return nil,'invalid_args' end
        if authority.bindings.companion~=args.generation then return nil,'stale_generation' end
        local state,reason=managementState(data);if not state then return nil,reason end
        local network,bindingError=managementBinding(data,args,false);if not network then return nil,bindingError end
        return {scopes={'session'},apply=function()
            network.credentialHash=args.credentialHash;network.bindingVersion=network.bindingVersion+1
            transaction.state.travelRequests=nil
            return {management='kick',generation=args.generation,campaignId=network.campaignId,
                companionId=network.companionId,bindingVersion=network.bindingVersion}
        end}
    end,true)
end
return Commands
