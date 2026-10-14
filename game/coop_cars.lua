-- Personal car selection does not change the party scene or journey. Arrival
-- geometry and transition duration are host-owned, never supplied by a guest.
local Players=require('game.coop_players')
local Leases=require('game.coop_leases')
local P=require('game.net.protocol')
local Cars={DURATION=.78}
function Cars.install(authority,context)
    authority:register('player.car',function(data,actorId,args,transaction)
        if not P.fields(args,{car=true}) or not P.integer(args.car,1,#data.trainCars) then return nil,'invalid_car' end
        local actor=Players.get(data,actorId); local state=context.actorState(actorId)
        if not state or state.screen~='game' or state.scene~='train' or data.scene~='train'
            or state.traveling or data.coop.journey or state.encounterActive or state.activityBlocked
            or actor.health<=0 then return nil,'car_unavailable' end
        if state.changingCar then return nil,'car_transition_pending' end
        if args.car==actor.activeCar then return nil,'same_car' end
        local from=actor.activeCar
        local x,y=context.carArrival(data,actorId,args.car,args.car>from)
        if not P.clock(x) or not P.clock(y) then return nil,'invalid_car_arrival' end
        return {scopes={'player:'..actorId},checkpoint=true,apply=function()
            actor.activeCar=args.car; actor.playerX=x; actor.playerY=y
            actor.playerFacing=args.car>from and 1 or -1
            Leases.releaseActor(transaction.state,actorId)
            return {personalCar=true,from=from,car=args.car,x=x,y=y,facing=actor.playerFacing,duration=Cars.DURATION}
        end}
    end)
end
return Cars
