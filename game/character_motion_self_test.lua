local Motion = require("game.character_motion")

local Test = {}

local function close(left,right,tolerance)
    return math.abs(left-right) <= (tolerance or 0.0001)
end

local function check(condition,message)
    if not condition then error("character motion test failed: "..message,2) end
end

local function actor()
    return {x=0,y=0,facing=1,velocityX=0,velocityY=0,intentX=1,intentY=0,
        animationDistance=0,idleClock=0,moving=false}
end

function Test.run()
    local directions={
        {0,-1,"walk_north",1,"idle_north"},
        {1,-1,"walk_northeast",1,"idle_northeast"},
        {1,0,"walk",1,"idle"},
        {1,1,"walk_southeast",1,"idle_southeast"},
        {0,1,"walk_south",1,"idle_south"},
        {-1,1,"walk_southeast",-1,"idle_southeast"},
        {-1,0,"walk",-1,"idle"},
        {-1,-1,"walk_northeast",-1,"idle_northeast"},
    }
    for _,expected in ipairs(directions) do
        local walk,walkMirror=Motion.directionalWalkAction(expected[1],expected[2])
        local idle,idleMirror=Motion.directionalIdleAction(expected[1],expected[2])
        check(walk==expected[3] and walkMirror==expected[4],"eight-sector walk mapping")
        check(idle==expected[5] and idleMirror==expected[4],"walk/idle direction pairing")
    end

    local authoredWest={
        {-1,1,"walk_southwest","idle_southwest"},
        {-1,0,"walk_west","idle_west"},
        {-1,-1,"walk_northwest","idle_northwest"},
    }
    for _,expected in ipairs(authoredWest) do
        local walk,walkMirror=Motion.directionalWalkAction(expected[1],expected[2],true)
        local idle,idleMirror=Motion.directionalIdleAction(expected[1],expected[2],true)
        check(walk==expected[3] and walkMirror==1,"authored west walk mapping")
        check(idle==expected[4] and idleMirror==1,"authored west idle mapping")
    end

    for frame=1,8 do
        check(Motion.frameForDistance(8,(frame-1)*20,20)==frame,"distance frame "..frame)
    end
    check(Motion.frameForDistance(8,160,20)==1,"distance loop seam")

    local profile=Motion.defaults
    local contactSpeed,contactAcceleration=Motion.sample(0,profile)
    local loadedSpeed,loadedAcceleration=Motion.sample(20,profile)
    local passingSpeed,passingAcceleration=Motion.sample(40,profile)
    local propulsionSpeed,propulsionAcceleration=Motion.sample(60,profile)
    check(loadedSpeed<contactSpeed and contactSpeed<passingSpeed and passingSpeed<propulsionSpeed,
        "gait speed pose order")
    check(loadedAcceleration<contactAcceleration and contactAcceleration<passingAcceleration
        and passingAcceleration<propulsionAcceleration,"gait acceleration pose order")
    local blendedSpeed=Motion.sample(30,profile)
    check(blendedSpeed>loadedSpeed and blendedSpeed<passingSpeed,"smooth gait interpolation")
    local oppositeContact=Motion.sample(80,profile)
    check(close(contactSpeed,oppositeContact),"opposite step repeats profile")

    local diagonal=actor()
    Motion.updateActor(diagonal,1,1,.1,{profile=profile,speed=100})
    check(math.sqrt(diagonal.velocityX^2+diagonal.velocityY^2)<=100.001,"normalized diagonal speed")

    local sliding=actor()
    Motion.updateActor(sliding,1,1,.1,{profile=profile,speed=100,
        move=function(oldX,_,_,nextY) return oldX,nextY end})
    check(close(sliding.x,0,.001) and sliding.y>0,"wall sliding")

    local blocked=actor()
    Motion.updateActor(blocked,1,0,.1,{profile=profile,speed=100,
        move=function(oldX,oldY) return oldX,oldY end})
    check(not blocked.moving and blocked.blocked and blocked.animationDistance==0,
        "blocked movement freezes gait")

    local moved=actor()
    local actual=Motion.updateActor(moved,1,0,.1,{profile=profile,speed=100})
    check(actual>0 and close(moved.animationDistance,actual),"actual displacement drives gait")
    local lastIntentX,lastIntentY=moved.intentX,moved.intentY
    Motion.updateActor(moved,0,0,.1,{profile=profile,speed=100})
    check(moved.intentX==lastIntentX and moved.intentY==lastIntentY,"idle retains final direction")

    local braking=actor()
    braking.velocityX=80
    braking.animationDistance=60
    Motion.updateActor(braking,0,0,.01,{profile=profile,speed=100})
    check(close(braking.velocityX,80-profile.deceleration*.01,.001),"release uses ordinary braking")

    local complete={}
    for _,action in ipairs(Motion.directionalActions) do complete[action]={} end
    check(Motion.hasDirectionalSet(complete),"complete directional set accepted")
    complete.idle_south=nil
    check(not Motion.hasDirectionalSet(complete),"incomplete directional set rejected")

    local completeWest={}
    for _,action in ipairs(Motion.authoredWestActions) do completeWest[action]={} end
    check(Motion.hasAuthoredWestSet(completeWest),"complete authored west set accepted")
    completeWest.idle_west=nil
    check(not Motion.hasAuthoredWestSet(completeWest),"partial authored west set rejected")

    print("CHARACTER_MOTION_TEST_OK")
    return true
end

return Test
