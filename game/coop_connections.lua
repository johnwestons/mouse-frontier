-- Local host administration crosses the same checked-save barrier as gameplay.
-- Callers retain newly generated raw credentials outside command arguments and
-- receipts, publishing them only after a durable result/retry checkpoint.
local P=require('game.net.protocol')
local Crypto=require('game.net.crypto')
local Players=require('game.coop_players')
local Commands={}
function Commands.install(authority,context)
    assert(type(context)=='table' and type(context.placeCompanion)=='function','companion spawn resolver required')
    local function register(name,prepare)
        authority:register(name,function(data,actorId,args)
            if authority.bindings.companion then return nil,'companion_connected' end
            if not authority.checkpoint then return nil,'checkpoint_required' end
            return prepare(data,args)
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
end
return Commands
