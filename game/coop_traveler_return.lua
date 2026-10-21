-- Freeze a final character before the client writes it home. Acknowledgement
-- permits another visitor only after the client has verified its local save.
local Players=require('game.coop_players')
local Traveler=require('game.coop_traveler')
local P=require('game.net.protocol')
local Returns={}
function Returns.install(authority)
    for _,command in ipairs({'traveler.return','traveler.ack','session.returnTraveler'}) do
        local ack=command=='traveler.ack'
        local hostReturn=command=='session.returnTraveler'
        authority:register(command,function(view,id,args,transaction)
            if hostReturn and id=='host' then id='companion' end
            local data=Players.campaignOf(view); local actor=data.players[id]
            if id~='companion' or not actor or not actor.travelIdentity then return nil,'traveler_required' end
            local identity=actor.travelIdentity
            if not P.fields(args,{tripId=true,serial=true}) or args.tripId~=identity.tripId or args.serial~=identity.serial then
                return nil,'traveler_visit_mismatch'
            end
            if ack and not actor.travelReturn then return nil,'traveler_not_returned' end
            if not ack and identity.status=='active' and (data.tacticalBattle or data.roamingEncounter
                or data.trainAmbush and data.trainAmbush.active or require('game.coop_last_stand_lifecycle').active(data)) then
                return nil,'traveler_combat_active'
            end
            local history=data.travelerHistory or {}
            local count=0; for _ in pairs(history) do count=count+1 end
            if ack and not history[identity.profileId] and count>=256 then return nil,'traveler_history_full' end
            return {scopes={'player:companion','session'},checkpoint=true,apply=function()
                if ack then
                    data.travelerHistory=history
                    history[identity.profileId]={tripId=identity.tripId,serial=identity.serial}
                    identity.status='closed'
                elseif not actor.travelReturn then
                    local profile={version=1,profileId=identity.profileId,tripId=identity.tripId,serial=identity.serial,
                        actor=Traveler.exportActor(data,id)}
                    actor.travelReturn={profile=assert(Traveler.pack(profile)),revision=data.coop.revision+1}
                    identity.status='returned'
                    require('game.coop_leases').releaseActor(transaction.state,id)
                end
                return {returned=true,acknowledged=identity.status=='closed'}
            end}
        end)
    end
end
return Returns
