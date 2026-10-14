-- One actor's movement rules, shared by authority and disposable prediction.
-- The caller owns timing and supplies collision. No save/scene writes occur.
local Motion=require('game.character_motion')
local Step={SPEED=185,SPRINT=1.7}
function Step.stop(actor)
    if actor then Motion.stopActor(actor); actor.moving=false end
end
function Step.advance(actor,record,input,dt,move)
    local x,y=input and input.x or 0,input and input.y or 0
    local profile=Motion.profileFor(record.character)
    if profile then
        return Motion.updateActor(actor,x,y,dt,{profile=profile,speed=Step.SPEED,
            speedScale=input and input.sprint and Step.SPRINT or 1,move=move})
    end
    local length=math.sqrt(x*x+y*y); local ox,oy=actor.x,actor.y
    actor.intentX,actor.intentY=x,y
    actor.locomotionMode=input and input.sprint and 'run' or 'walk'
    if length>0 then
        -- Preserve the existing normalized response for legacy character art.
        x,y=x/length,y/length
        if x~=0 then actor.facing=x>0 and 1 or -1 end
        local speed=Step.SPEED*(input.sprint and Step.SPRINT or 1)
        actor.x,actor.y=move(ox,oy,ox+x*speed*dt,oy+y*speed*dt)
    end
    actor.velocityX=(actor.x-ox)/dt; actor.velocityY=(actor.y-oy)/dt
    local distance=math.sqrt((actor.x-ox)^2+(actor.y-oy)^2)
    actor.moving=distance>.0001
    actor.animationDistance=(actor.animationDistance or 0)+distance
    actor.idleClock=actor.moving and 0 or (actor.idleClock or 0)+dt
    return distance
end
return Step
