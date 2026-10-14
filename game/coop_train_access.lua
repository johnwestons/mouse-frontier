-- Read-only train assistance facts used by detached guest controls.
local Players=require('game.coop_players')
local Contract=require('game.coop_item_contract')
local Config=require('game.config')
local Access={}
function Access.nearFire(data,state,car)
    car=car or Config.trainCar
    return state and state.screen=='game' and state.scene=='train' and data.scene=='train' and data.activeCar==1
        and type(state.x)=='number' and type(state.y)=='number'
        and (state.x-car.x-165)^2+(state.y-car.y-240)^2<=95^2
end
function Access.coal(data)
    for index=1,data.inventoryCapacity do
        local name=data.inventory[index]
        if name=='coal-chunk' or name=='coal-bucket' then
            local ref={kind='inventory',index=index}
            return ref,Contract.selection(data,nil,ref)
        end
    end
end
function Access.expected(data,command,actorId)
    data=Players.campaignOf(data)
    local expected={resources=data.coop.revisions.resources or 0,train=data.coop.revisions.train or 0}
    if command=='train.fuel' then expected['player:'..actorId]=data.coop.revisions['player:'..actorId] or 0 end
    return expected
end
return Access
