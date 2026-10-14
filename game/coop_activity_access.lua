-- Read-only activity eligibility and revision scopes shared by UI and host.
local Players=require('game.coop_players')
local Access={}
Access.resources={maintenance='train:maintenance',weaponRepair='train:weapon-repair',sewing='train:sewing'}
function Access.train(data,state,kind)
    return data and data.health>0 and state and state.screen=='game' and state.scene=='train'
        and data.scene=='train' and data.stopped==true and not state.traveling and not state.changingCar
        and not state.encounterActive and not (data.trainAmbush and data.trainAmbush.active)
        and (not state.activityBlocked or kind and state.activeActivity==kind)
end
function Access.expected(data,actorId,command,kind)
    data=Players.campaignOf(data)
    kind=kind or (command:match('^(%w+)%.'))
    local resource=Access.resources[kind]; if not resource then return nil end
    local scopes={'activity:'..resource}
    if command=='weaponRepair.acquire' or command=='weaponRepair.complete' then scopes[#scopes+1]='player:'..actorId end
    if command=='maintenance.complete' or command=='weaponRepair.complete' then scopes[#scopes+1]='resources' end
    if command=='maintenance.complete' then scopes[#scopes+1]='train' end
    local expected={}; for _,scope in ipairs(scopes) do expected[scope]=data.coop.revisions[scope] or 0 end
    return expected
end
return Access
