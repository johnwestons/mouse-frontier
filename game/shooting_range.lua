local SoundProfiles=require("game.weapon_sound_profiles")
local FirstPersonWeaponManifest=require("game.first_person_weapon_manifest")
local Range={}

Range.version=3
Range.roundSeconds=45
Range.stageLengths={30,45,60,90}
Range.hostStops={2,8,14,20,26,32,38,44,50}
Range.motionModes={"stationary","moving","mixed"}
Range.targetTypes={"paper","steel","clay"}
Range.targetPatterns={"stay-up","pop-up"}
Range.motionScoreMultipliers={stationary=1,mixed=1.15,moving=1.30}
Range.ammoBundles={
    rocks={amount=16,cost=1},arrows={amount=8,cost=2},["ball-bearings"]={amount=12,cost=2},
    ["12-gauge"]={amount=6,cost=3},["22lr"]={amount=18,cost=3},default={amount=12,cost=3},
}

local hostLookup={}
for _,location in ipairs(Range.hostStops) do hostLookup[location]=true end

local lanes={
    {x=205,y=332,scale=.27,radius=34},
    {x=370,y=300,scale=.24,radius=29},
    {x=525,y=350,scale=.29,radius=37},
    {x=690,y=292,scale=.23,radius=28},
    {x=800,y=382,scale=.31,radius=40},
    {x=470,y=255,scale=.26,radius=27},
}

local lobbyRows={
    {kind="weapon",y=270,label="WEAPON"},
    {kind="motion",y=365,label="TARGET MOTION"},
    {kind="material",y=460,label="TARGET TYPE"},
}

local DEFAULT_SIGHT_ANCHOR={x=.5,y=.35}

local function title(value)
    return (value or "unknown"):gsub("%-"," "):gsub("(%a)([%w']*)",function(a,b) return a:upper()..b end)
end

local function contains(list,value)
    for _,entry in ipairs(list or {}) do if entry==value then return true end end
    return false
end

local function hit(rect,x,y)
    return rect and x>=rect.x and x<=rect.x+rect.w and y>=rect.y and y<=rect.y+rect.h
end

local function availableAmmo(data,combat)
    if not combat or not combat.ammo then return math.huge end
    return math.max(0,math.floor(tonumber(data and data.ammo and data.ammo[combat.ammo]) or 0))
end

local function weaponDurability(data,name)
    local value=data and data.weaponDurability and data.weaponDurability[name]
    return math.max(0,math.min(100,math.floor(tonumber(value) or 100)))
end

local function weaponIssue(data,catalog,name)
    local combat=name and catalog.weaponCombat[name]
    if not combat or combat.kind~="ranged" then return "NOT A RANGED WEAPON" end
    if weaponDurability(data,name)<=0 then return "THIS WEAPON IS BROKEN" end
    if availableAmmo(data,combat)<=0 then return "THIS WEAPON NEEDS AMMO" end
    return nil
end

local function weaponReady(data,catalog,name)
    return weaponIssue(data,catalog,name)==nil
end

function Range.isHost(location)
    return hostLookup[math.floor(tonumber(location) or 0)]==true
end

function Range.ensure(layout,location,settlements)
    if not layout or not Range.isHost(location) then return nil end
    if type(layout.shootingRange)~="table" or layout.shootingRange.version~=Range.version then
        local x,y=760,565
        if settlements and settlements.clamp then x,y=settlements.clamp(x,y,location) end
        local previous=type(layout.shootingRange)=="table" and layout.shootingRange or {}
        layout.shootingRange={version=Range.version,x=x,y=y,rewarded=previous.rewarded==true,rewardTier=previous.rewardTier,
            highScores=type(previous.highScores)=="table" and previous.highScores or {},preferences=previous.preferences}
    end
    local spot=layout.shootingRange
    spot.highScores=type(spot.highScores)=="table" and spot.highScores or {}
    spot.preferences=type(spot.preferences)=="table" and spot.preferences or {motion="stationary",material="paper"}
    local rewardTier=tonumber(spot.rewardTier)
    if rewardTier==nil then rewardTier=spot.rewarded==true and 3 or 0 end
    spot.rewardTier=math.max(0,math.min(3,math.floor(rewardTier)))
    spot.rewarded=spot.rewardTier>0
    spot.x=tonumber(spot.x) or 760; spot.y=tonumber(spot.y) or 565
    return spot
end

function Range.near(spot,x,y)
    if not spot then return false end
    local dx,dy=(x or 0)-spot.x,(y or 0)-spot.y
    return dx*dx+dy*dy<=66*66
end

function Range.scoreMultiplier(session)
    local mode=type(session)=="table" and session.motion or session
    return Range.motionScoreMultipliers[mode] or 1
end

function Range.ownedWeapons(data,catalog)
    local result,seen={},{}
    local function add(name)
        local combat=name and catalog.weaponCombat[name]
        if combat and combat.kind=="ranged" and not seen[name] then
            seen[name]=true; result[#result+1]=name
        end
    end
    for _,name in pairs(data.equipment or {}) do add(name) end
    for _,name in pairs(data.inventory or {}) do add(name) end
    table.sort(result,function(a,b)
        local pa,pb=0,0
        for index,name in ipairs(catalog.weaponProgression or {}) do
            if name==a then pa=index elseif name==b then pb=index end
        end
        return pa==pb and a<b or pa<pb
    end)
    return result
end

local function firstReady(data,catalog,weapons)
    for index,name in ipairs(weapons) do if weaponReady(data,catalog,name) then return index end end
    return nil
end

local function firstServiceable(data,weapons)
    for index,name in ipairs(weapons) do if weaponDurability(data,name)>0 then return index end end
    return nil
end

local function clearWeaponViewSequence(session)
    session.weaponViewSequence=nil
    session.weaponViewState=nil
    session.weaponViewPlacement=nil
end

local function applyWeaponViewSequenceStep(session)
    local sequence=session.weaponViewSequence
    local step=sequence and sequence.definition.steps[sequence.index]
    if not step then return false end
    session.weaponViewState=step.state
    session.weaponViewPlacement=step.placement
    return true
end

local function startWeaponViewSequence(session)
    local definition=FirstPersonWeaponManifest.shotSequenceFor(session.weapon)
    clearWeaponViewSequence(session)
    if not definition then return false end
    session.weaponViewSequence={definition=definition,index=1,elapsed=0}
    return applyWeaponViewSequenceStep(session)
end

local function updateWeaponViewSequence(session,dt)
    local sequence=session.weaponViewSequence
    if not sequence then return end
    local remaining=dt
    while sequence do
        local step=sequence.definition.steps[sequence.index]
        if not step or step.duration==nil then return end
        local untilNext=step.duration-sequence.elapsed
        if remaining<untilNext then
            sequence.elapsed=sequence.elapsed+remaining
            return
        end
        remaining=remaining-untilNext
        sequence.index=sequence.index+1
        sequence.elapsed=0
        if applyWeaponViewSequenceStep(session) then
            sequence=session.weaponViewSequence
        else
            local restoresLoaded=sequence.definition.restoresLoaded==true
            clearWeaponViewSequence(session)
            if restoresLoaded then
                session.loaded=session.capacity or 1
                session.needsReload=false
                if session.message=="PROJECTILE RETURNING" or session.message=="PROJECTILE NOT READY" then session.message=nil end
            end
            return
        end
    end
end

local function loadWeapon(session,data,catalog)
    session.weapon=session.weapons[session.selected]
    local combat=catalog.weaponCombat[session.weapon]
    session.ammoType=combat.ammo
    session.capacity=math.max(1,math.floor(combat.capacity or 1))
    session.loaded=math.min(session.capacity,availableAmmo(data,combat))
    session.needsReload=false
    clearWeaponViewSequence(session)
end

function Range.new(data,spot,catalog,options)
    spot.preferences=type(spot.preferences)=="table" and spot.preferences or {motion="stationary",material="paper"}
    local stageLength=math.floor(tonumber(spot.preferences.stageLength) or Range.roundSeconds)
    local validStageLength=false
    for _,value in ipairs(Range.stageLengths) do if stageLength==value then validStageLength=true; break end end
    if not validStageLength then stageLength=Range.roundSeconds end
    local targetPattern=spot.preferences.targetPattern=="pop-up" and "pop-up" or "stay-up"
    local weapons=Range.ownedWeapons(data,catalog)
    local selected=firstReady(data,catalog,weapons) or firstServiceable(data,weapons)
    if #weapons==0 then return nil,"Bring a ranged weapon if you want to practice at the range." end
    if not selected then return nil,"Your ranged weapons need repairs before you can practice at the range." end
    local session={
        phase="lobby",spot=spot,weapons=weapons,selected=selected,location=data.location,
        npc=options and options.npc,aimX=480,aimY=330,clock=0,score=0,shots=0,hits=0,
        targets={},spawnIndex=0,nextSpawn=.15,time=Range.roundSeconds,recoil=0,message=nil,
        menuRow=1,motion=spot.preferences.motion or "stationary",material=spot.preferences.material or "paper",
        aimMode="hip",needsReload=false,reloadPulse=0,targetPattern=targetPattern,stageLength=stageLength,
    }
    loadWeapon(session,data,catalog)
    return session
end

local function spawnTarget(session)
    session.spawnIndex=session.spawnIndex+1
    local lane=lanes[((session.spawnIndex-1)%#lanes)+1]
    local moving=session.motion=="moving" or (session.motion=="mixed" and session.spawnIndex%2==0)
    local direction=session.spawnIndex%2==0 and 1 or -1
    local material=session.material
    local sprite=material=="paper" and ((session.spawnIndex-1)%4+1) or material=="steel" and ((session.spawnIndex-1)%4+5) or 10
    local points=math.floor(100*Range.scoreMultiplier(session)+.5)
    session.targets[#session.targets+1]={
        x=lane.x,y=lane.y,baseX=lane.x,scale=lane.scale,material=material,sprite=sprite,
        radius=lane.radius,points=points,life=session.targetPattern=="stay-up" and math.huge or (moving and 3.4 or 2.8),age=0,
        velocity=moving and direction*(48+session.spawnIndex%4*8) or 0,hit=false,impacts={},
    }
end

local function resetRound(session,data,catalog)
    session.phase="play"; session.clock=0; session.score=0; session.shots=0; session.hits=0
    session.targets={}; session.spawnIndex=0; session.nextSpawn=.1; session.time=session.stageLength or Range.roundSeconds
    session.recoil=0; session.message=nil; session.completed=false; session.result=nil
    session.aimMode=session.aimMode or "hip"; session.needsReload=false; session.reloadPulse=0
    session.spot.preferences={motion=session.motion,material=session.material,targetPattern=session.targetPattern,stageLength=session.stageLength}
    loadWeapon(session,data,catalog)
end

function Range.update(session,dt)
    if not session or session.phase~="play" then return nil end
    dt=math.min(.08,math.max(0,dt or 0))
    session.clock=session.clock+dt; session.time=math.max(0,session.time-dt)
    session.recoil=math.max(0,session.recoil-dt*32)
    updateWeaponViewSequence(session,dt)
    session.reloadPulse=(session.reloadPulse or 0)+dt
    session.nextSpawn=session.nextSpawn-dt
    if session.nextSpawn<=0 and #session.targets<4 then
        spawnTarget(session)
        session.nextSpawn=.8+(session.spawnIndex%3)*.18
    end
    for index=#session.targets,1,-1 do
        local target=session.targets[index]
        target.age=target.age+dt; target.life=target.life-dt
        if target.breaking then target.breaking=target.breaking+dt end
        target.x=target.x+target.velocity*dt
        if target.x<145 or target.x>830 then target.velocity=-target.velocity end
        if target.life<=0 then table.remove(session.targets,index) end
    end
    if session.time<=0 and not session.completed then session.completed=true; return "complete" end
end

function Range.sway(session,catalog)
    local family=catalog.weaponFamily(session.weapon)
    local amount=family=="slingshots" and 7 or family=="bows" and 5 or 3.5
    if session.aimMode=="sights" then amount=amount*.28 end
    return math.sin(session.clock*1.75)*amount,math.sin(session.clock*2.31+.8)*amount*.72-session.recoil
end

local function shoot(session,data,catalog,x,y)
    local combat=catalog.weaponCombat[session.weapon]
    if session.loaded<=0 then
        if not combat.ammo then
            session.needsReload=false
            session.message=session.weaponViewSequence and "PROJECTILE RETURNING" or "PROJECTILE NOT READY"
        else
            session.needsReload=true; session.message="RELOAD REQUIRED"
        end
        return "dry"
    end
    if combat.ammo then
        local reserve=availableAmmo(data,combat)
        if reserve<=0 then session.loaded=0; session.needsReload=true; session.message="OUT OF "..string.upper(combat.ammo); return "dry" end
        data.ammo[combat.ammo]=reserve-1
    end
    session.loaded=session.loaded-1; session.shots=session.shots+1
    session.needsReload=session.loaded<=0 and combat.ammo~=nil
    startWeaponViewSequence(session)
    local swayX,swayY=Range.sway(session,catalog)
    local shotX,shotY=(x or session.aimX)+swayX,(y or session.aimY)+swayY
    session.recoil=catalog.weaponFamily(session.weapon)=="firearms" and 12 or 7
    local best,bestDistance
    for _,target in ipairs(session.targets) do
        local dx,dy=shotX-target.x,shotY-target.y
        local distance=math.sqrt(dx*dx+dy*dy)
        local bonus=session.weapon:find("shotgun") and 13 or 0
        if distance<=target.radius+bonus and (not bestDistance or distance<bestDistance) then best,bestDistance=target,distance end
    end
    if best then
        if best.material=="clay" then
            if not best.hit then best.breaking=.001; best.life=math.min(best.life,.48) end
        else
            local impact={offsetX=shotX-best.x,offsetY=shotY-best.y,variant=(session.shots-1)%4+1,material=best.material}
            best.impacts[#best.impacts+1]=impact
        end
        if not best.hit then
            best.hit=true; session.hits=session.hits+1
            local precision=math.max(.25,1-bestDistance/(best.radius+1))
            session.score=session.score+math.floor(best.points*precision+25)
        end
        session.message=session.needsReload and "RELOAD REQUIRED" or "HIT"; return "shot"
    end
    session.message=session.needsReload and "RELOAD REQUIRED" or "MISS"; return "shot"
end

function Range.reload(session,data,catalog)
    if session.phase~="play" then return false end
    local combat=catalog.weaponCombat[session.weapon]
    if not combat.ammo then
        session.needsReload=false
        session.message=session.weaponViewSequence and "PROJECTILE RETURNING" or "READY"
        return false
    end
    clearWeaponViewSequence(session)
    local amount=math.min(session.capacity,availableAmmo(data,combat))
    if amount<=session.loaded then session.needsReload=session.loaded<=0 and combat.ammo~=nil; session.message=combat.ammo and "NO MORE AMMO" or "READY"; return false end
    session.loaded=amount; session.needsReload=false; session.message="RELOADED"; return true
end

function Range.select(session,data,catalog,direction)
    if session.phase~="lobby" and session.phase~="results" then return false end
    session.selected=((session.selected-1+(direction or 1))%#session.weapons)+1
    loadWeapon(session,data,catalog); session.message=nil
    return true
end

local function cycle(list,value,direction)
    local selected=1
    for index,entry in ipairs(list) do if entry==value then selected=index; break end end
    return list[((selected-1+(direction or 1))%#list)+1]
end

lobbyRows={
    {kind="weapon",label="PRACTICE WEAPON",y=216},
    {kind="motion",label="TARGET MOTION",y=278},
    {kind="material",label="TARGET MATERIAL",y=340},
    {kind="pattern",label="TARGET STYLE",y=402},
    {kind="length",label="STAGE LENGTH",y=464},
}

function Range.changeSetup(session,data,catalog,kind,direction)
    if session.phase~="lobby" and session.phase~="results" then return false end
    if kind=="weapon" then return Range.select(session,data,catalog,direction) end
    if kind=="motion" then session.motion=cycle(Range.motionModes,session.motion,direction)
    elseif kind=="material" then session.material=cycle(Range.targetTypes,session.material,direction)
    elseif kind=="pattern" then session.targetPattern=cycle(Range.targetPatterns,session.targetPattern,direction)
    elseif kind=="length" then session.stageLength=cycle(Range.stageLengths,session.stageLength,direction)
    else return false end
    session.spot.preferences={motion=session.motion,material=session.material,targetPattern=session.targetPattern,stageLength=session.stageLength}; session.message=nil
    return true
end

function Range.ammoOffer(session,catalog)
    if not session or not catalog then return nil end
    local combat=catalog.weaponCombat[session.weapon] or {}
    if not combat.ammo then return nil end
    local bundle=Range.ammoBundles[combat.ammo] or Range.ammoBundles.default
    return {ammo=combat.ammo,amount=bundle.amount,cost=bundle.cost}
end

function Range.buyAmmo(session,data,catalog)
    if not session or session.phase~="lobby" then return false end
    local offer=Range.ammoOffer(session,catalog)
    if not offer then session.message="THIS WEAPON DOES NOT NEED AMMO"; return false end
    local scrap=math.max(0,math.floor(tonumber(data.scrap) or 0))
    if scrap<offer.cost then session.message="NEED "..offer.cost.." SCRAP FOR AMMO"; return false end
    data.ammo=type(data.ammo)=="table" and data.ammo or {}
    data.scrap=scrap-offer.cost
    data.ammo[offer.ammo]=availableAmmo(data,{ammo=offer.ammo})+offer.amount
    session.message="BOUGHT "..offer.amount.." "..string.upper(offer.ammo).." FOR "..offer.cost.." SCRAP"
    return true,offer
end

function Range.toggleAim(session)
    if not session or session.phase~="play" then return false end
    session.aimMode=session.aimMode=="sights" and "hip" or "sights"
    return true
end

function Range.setAim(session,aiming)
    if not session or session.phase~="play" then return false end
    session.aimMode=aiming and "sights" or "hip"
    return true
end

function Range.setWeaponViewState(session,state)
    if not session then return false end
    clearWeaponViewSequence(session)
    session.weaponViewState=type(state)=="string" and state~="" and state or nil
    return true
end

function Range.returnToSetup(session)
    if not session or session.phase~="play" then return false end
    clearWeaponViewSequence(session)
    session.phase="lobby"; session.targets={}; session.recoil=0; session.needsReload=false
    session.time=session.stageLength or Range.roundSeconds
    session.message="COURSE RESET - ADJUST YOUR SETUP"
    return true
end

function Range.weaponViewPlacement(session)
    if session and (session.weaponViewPlacement=="hip" or session.weaponViewPlacement=="sights") then
        return session.weaponViewPlacement
    end
    return session and session.aimMode=="sights" and "sights" or "hip"
end

function Range.mousemoved(session,x,y)
    if not session or session.phase~="play" then return end
    session.aimX=math.max(30,math.min(930,x)); session.aimY=math.max(55,math.min(625,y))
end

function Range.mousepressed(session,x,y,data,catalog,button)
    if not session then return nil end
    button=button or 1
    if button==2 and session.phase=="play" then Range.setAim(session,true); return "aim" end
    if session.phase=="lobby" then
        for index,row in ipairs(lobbyRows) do
            if hit({x=218,y=row.y-21,w=62,h=46},x,y) then session.menuRow=index; Range.changeSetup(session,data,catalog,row.kind,-1); return "select" end
            if hit({x=680,y=row.y-21,w=62,h=46},x,y) then session.menuRow=index; Range.changeSetup(session,data,catalog,row.kind,1); return "select" end
        end
        if hit({x=185,y=542,w=290,h=54},x,y) then
            local purchased=Range.buyAmmo(session,data,catalog); return purchased and "purchase" or "dry"
        end
        if hit({x=500,y=542,w=275,h=54},x,y) then
            if weaponReady(data,catalog,session.weapon) then resetRound(session,data,catalog); return "start" end
            session.message=weaponIssue(data,catalog,session.weapon); return "dry"
        end
        if hit({x=800,y=654,w=130,h=42},x,y) then return "close" end
    elseif session.phase=="play" then
        if hit({x=18,y=654,w=126,h=42},x,y) then return Range.reload(session,data,catalog) and "reload" or "dry" end
        if hit({x=154,y=654,w=126,h=42},x,y) then Range.toggleAim(session); return "aim" end
        if hit({x=680,y=654,w=126,h=42},x,y) then Range.returnToSetup(session); return "setup" end
        if hit({x=816,y=654,w=126,h=42},x,y) then return "close" end
        Range.mousemoved(session,x,y)
        if button==4 then return "aim" end
        return shoot(session,data,catalog,session.aimX,session.aimY)
    elseif session.phase=="results" then
        if hit({x=238,y=548,w=150,h=58},x,y) then
            if weaponReady(data,catalog,session.weapon) then resetRound(session,data,catalog); return "start" end
            session.message=weaponIssue(data,catalog,session.weapon); return "dry"
        end
        if hit({x=405,y=548,w=150,h=58},x,y) then session.phase="lobby"; session.message=nil; return "setup" end
        if hit({x=572,y=548,w=150,h=58},x,y) then return "close" end
    end
end

function Range.keypressed(session,key,data,catalog)
    if key=="escape" or key=="q" then return "close" end
    if session.phase=="lobby" then
        if key=="up" or key=="w" then session.menuRow=((session.menuRow-2)%#lobbyRows)+1; return "select" end
        if key=="down" or key=="s" then session.menuRow=(session.menuRow%#lobbyRows)+1; return "select" end
        if key=="left" or key=="a" then Range.changeSetup(session,data,catalog,lobbyRows[session.menuRow].kind,-1); return "select" end
        if key=="right" or key=="d" then Range.changeSetup(session,data,catalog,lobbyRows[session.menuRow].kind,1); return "select" end
        if key=="b" then local purchased=Range.buyAmmo(session,data,catalog); return purchased and "purchase" or "dry" end
        if key=="return" or key=="space" then
            if weaponReady(data,catalog,session.weapon) then resetRound(session,data,catalog); return "start" end
            session.message=weaponIssue(data,catalog,session.weapon); return "dry"
        end
    elseif session.phase=="play" then
        if key=="r" then return Range.reload(session,data,catalog) and "reload" or "dry" end
        if key=="tab" then Range.returnToSetup(session); return "setup" end
        if key=="lshift" or key=="rshift" then Range.toggleAim(session); return "aim" end
        if key=="space" then return shoot(session,data,catalog,session.aimX,session.aimY) end
    elseif session.phase=="results" and (key=="return" or key=="space") then session.phase="lobby"; return "setup" end
end

function Range.sound(session,catalog)
    local family=catalog.weaponFamily(session.weapon)
    if family=="bows" then return "bow" end
    if family=="slingshots" then return "bow" end
    return "gunshot"
end

function Range.soundProfile(session,catalog)
    return session and SoundProfiles.forWeapon(session.weapon,catalog) or nil
end

function Range.complete(session,data,spot,stopHelp)
    if not session or session.phase~="play" then return session and session.result end
    local accuracy=session.shots>0 and session.hits/session.shots or 0
    local rank=session.score>=1150 and accuracy>=.55 and "SHARPSHOOTER" or session.score>=650 and "MARKSMOUSE" or session.score>=250 and "TRAIL HAND" or "BEGINNER"
    local previous=math.floor(tonumber(spot.highScores[session.weapon]) or 0)
    spot.highScores[session.weapon]=math.max(previous,session.score)
    local earnedTier=session.score>=1150 and accuracy>=.55 and 3 or session.score>=550 and 2 or session.hits>0 and 1 or 0
    local previousTier=tonumber(spot.rewardTier)
    if previousTier==nil then previousTier=spot.rewarded==true and 3 or 0 end
    previousTier=math.max(0,math.min(3,math.floor(previousTier)))
    local rewardTier=math.max(previousTier,earnedTier)
    local gained=rewardTier-previousTier
    spot.rewardTier=rewardTier; spot.rewarded=rewardTier>0
    if gained>0 then stopHelp.add(data,gained,"shooting-range",session.npc,data.location) end
    session.result={score=session.score,accuracy=accuracy,rank=rank,gained=gained,rewardTier=rewardTier,earnedRewardTier=earnedTier,
        highScore=spot.highScores[session.weapon],newBest=session.score>previous}
    session.phase="results"; session.message=nil
    return session.result
end

local targetQuadCache=setmetatable({},{__mode="k"})
local impactQuadCache=setmetatable({},{__mode="k"})
local function atlasQuads(image,columns,rows,cache)
    if not image then return nil end
    if cache[image] then return cache[image] end
    local width,height=image:getDimensions(); local cellW=math.floor(width/columns); local cellH=math.floor(height/rows)
    local quads={cellW=cellW,cellH=cellH}
    for index=1,columns*rows do
        local column,row=(index-1)%columns,math.floor((index-1)/columns)
        quads[index]=love.graphics.newQuad(column*cellW,row*cellH,cellW,cellH,width,height)
    end
    cache[image]=quads; return quads
end

local function drawButton(label,rect,enabled)
    love.graphics.setColor(enabled==false and .16 or .28,enabled==false and .15 or .20,enabled==false and .14 or .10,.94)
    love.graphics.rectangle("fill",rect.x,rect.y,rect.w,rect.h,7,7)
    love.graphics.setColor(enabled==false and .45 or .93,enabled==false and .43 or .75,enabled==false and .40 or .30,1)
    love.graphics.rectangle("line",rect.x,rect.y,rect.w,rect.h,7,7)
    love.graphics.printf(label,rect.x,rect.y+rect.h/2-7,rect.w,"center")
end

local function drawWeapon(ui,name)
    local atlas=ui.atlasItems and ui.atlasItems[name]
    local image=ui.propImages and ui.propImages[name]
    love.graphics.setColor(1,1,1,1)
    if atlas then
        local scale=math.min(230/atlas.w,150/atlas.h)
        love.graphics.draw(atlas.image,atlas.quad,930,650,-.10,scale,scale,atlas.w,atlas.h)
    elseif image then
        local width,height=image:getDimensions(); local scale=math.min(230/width,150/height)
        love.graphics.draw(image,930,650,-.10,scale,scale,width,height)
    end
end

local HIP_CURSOR_OFFSET_X=472
local HIP_CURSOR_OFFSET_Y=376

local function drawFirstPersonWeapon(assets,ui,session,aimX,aimY,swayX,swayY,placement)
    local views=assets and assets.weaponViews and assets.weaponViews[session.weapon]
    local state=session.weaponViewState or session.aimMode
    local image
    if assets and assets.weaponViews and type(assets.weaponViews.get)=="function" then
        views=assets.weaponViews
        image=views:get(session.weapon,state)
        if not image and state~=session.aimMode then image=views:get(session.weapon,session.aimMode) end
    else
        image=views and (views[state] or views[session.aimMode])
    end
    if not image then drawWeapon(ui,session.weapon); return false end
    local width,height=image:getDimensions()
    love.graphics.setColor(1,1,1,1)
    if placement=="sights" then
        local anchor=DEFAULT_SIGHT_ANCHOR
        if views and type(views.anchor)=="function" then anchor=select(1,views:anchor(session.weapon)) end
        local scale=math.min(560/width,650/height)
        love.graphics.draw(image,aimX-anchor.x*width*scale,aimY-anchor.y*height*scale,0,scale,scale)
    else
        local scale=math.min(540/width,540/height)
        local artX=aimX+HIP_CURSOR_OFFSET_X
        local artY=aimY+HIP_CURSOR_OFFSET_Y
        love.graphics.draw(image,artX,artY,0,scale,scale,width,height)
    end
    return true
end


function Range.releaseWeaponViews(assets)
    local views=assets and assets.weaponViews
    if views and type(views.release)=="function" then views:release(); return true end
    return false
end

function Range.draw(session,data,assets,ui,catalog,mobile)
    local background=assets and assets.background
    if background then
        love.graphics.setColor(1,1,1); love.graphics.draw(background,0,0,0,960/background:getWidth(),720/background:getHeight())
    else love.graphics.setColor(.18,.12,.07); love.graphics.rectangle("fill",0,0,960,720) end
    love.graphics.setColor(0,0,0,.18); love.graphics.rectangle("fill",0,0,960,720)

    if session.phase=="play" then
        local combat=catalog.weaponCombat[session.weapon] or {}
        local targetImage=assets and assets.targets; local targetQuads=atlasQuads(targetImage,4,3,targetQuadCache)
        local impactImage=assets and assets.impacts; local impactQuads=atlasQuads(impactImage,4,2,impactQuadCache)
        for _,target in ipairs(session.targets) do
            local sprite=target.sprite
            if target.material=="clay" and target.breaking then sprite=target.breaking<.13 and 11 or 12 end
            if targetImage and targetQuads and targetQuads[sprite] then
                local reveal=session.targetPattern=="pop-up" and math.max(0,math.min(1,target.age/.15,target.life/.15)) or 1
                love.graphics.setColor(1,1,1,(target.hit and .88 or 1)*reveal)
                love.graphics.draw(targetImage,targetQuads[sprite],target.x,target.y+(1-reveal)*18,0,target.scale,target.scale,targetQuads.cellW/2,targetQuads.cellH*.46)
            end
            for _,impact in ipairs(target.impacts) do
                local index=impact.variant+(impact.material=="steel" and 4 or 0)
                if impactImage and impactQuads and impactQuads[index] then
                    local scale=16/math.max(impactQuads.cellW,impactQuads.cellH)
                    love.graphics.setColor(1,1,1,1)
                    love.graphics.draw(impactImage,impactQuads[index],target.x+impact.offsetX,target.y+impact.offsetY,0,scale,scale,impactQuads.cellW/2,impactQuads.cellH/2)
                end
            end
        end
        love.graphics.setColor(.08,.055,.035,.91); love.graphics.rectangle("fill",14,12,210,82,8,8); love.graphics.rectangle("fill",736,12,210,82,8,8)
        love.graphics.setColor(1,.88,.58); love.graphics.print(string.format("TIME  %02d",math.ceil(session.time)),28,24,0,1.15,1.15)
        love.graphics.print("AMMO  "..(combat.ammo and tostring(session.loaded) or "--"),28,58)
        love.graphics.printf("SCORE\n"..session.score,750,24,180,"center")
        local sx,sy=Range.sway(session,catalog); local x,y=session.aimX+sx,session.aimY+sy
        local placement=Range.weaponViewPlacement(session)
        drawFirstPersonWeapon(assets,ui,session,x,y,sx,sy,placement)
        if placement=="sights" then
            love.graphics.setColor(1,.25,.16,.78); love.graphics.circle("fill",x,y,3); love.graphics.circle("line",x,y,7)
        else
            love.graphics.setColor(1,.25,.16,.95); love.graphics.circle("line",x,y,13); love.graphics.line(x-20,y,x-5,y); love.graphics.line(x+5,y,x+20,y); love.graphics.line(x,y-20,x,y-5); love.graphics.line(x,y+5,x,y+20)
        end
        if session.needsReload then
            local pulse=.72+.28*math.abs(math.sin((session.reloadPulse or 0)*5))
            love.graphics.setColor(.32,.035,.02,.94); love.graphics.rectangle("fill",310,108,340,58,8,8)
            love.graphics.setColor(1,.28,.12,pulse); love.graphics.rectangle("line",310,108,340,58,8,8)
            love.graphics.printf(mobile and "RELOAD REQUIRED  —  TAP RELOAD" or "RELOAD REQUIRED  —  PRESS R",320,128,320,"center",0,1.25,1.25)
        elseif session.message then love.graphics.setColor(1,.45,.25); love.graphics.printf(session.message,340,112,280,"center",0,1.15,1.15) end
        local reloadLabel=combat.ammo and (session.needsReload and "RELOAD!  [R]" or "RELOAD  [R]")
            or (session.weaponViewSequence and "RETURNING" or "REUSABLE")
        if mobile then reloadLabel=combat.ammo and (session.needsReload and "RELOAD!" or "RELOAD") or reloadLabel end
        drawButton(reloadLabel,{x=18,y=654,w=126,h=42},combat.ammo~=nil)
        drawButton(session.aimMode=="sights" and "AIMING" or (mobile and "AIM" or "AIM  [RMB]"),{x=154,y=654,w=126,h=42},true)
        drawButton(mobile and "SETUP" or "SETUP  [TAB]",{x=680,y=654,w=126,h=42},true)
        drawButton(mobile and "LEAVE" or "LEAVE  [Q]",{x=816,y=654,w=126,h=42},true)
        if mobile then
            love.graphics.setColor(1,.88,.58)
            love.graphics.printf("DRAG TO AIM  •  TAP FIRE TO SHOOT",292,620,376,"center",0,.78,.78)
        end
        love.graphics.setColor(1,.88,.58); love.graphics.printf(title(session.weapon).."  |  "..string.upper(session.motion).." "..string.upper(session.material)
            .."  |  "..string.upper(session.targetPattern).."  |  "..session.stageLength.." SEC",292,676,376,"center",0,.78,.78)
        return
    end

    love.graphics.setColor(.055,.04,.03,.91); love.graphics.rectangle("fill",154,92,652,544,12,12)
    love.graphics.setColor(.87,.65,.25); love.graphics.rectangle("line",154,92,652,544,12,12)
    if session.phase=="lobby" then
        love.graphics.setColor(1,.86,.58); love.graphics.printf("COMMUNITY TARGET RANGE",180,126,600,"center",0,1.35,1.35)
        love.graphics.setColor(.92,.86,.72); love.graphics.printf("Choose a weapon and course. Live ammunition is used; more is sold here for scrap.",220,158,520,"center",0,.9,.9)
        local combat=catalog.weaponCombat[session.weapon]; local reserve=availableAmmo(data or {},combat); local durability=weaponDurability(data,session.weapon)
        for index,row in ipairs(lobbyRows) do
            local selected=session.menuRow==index
            love.graphics.setColor(selected and 1 or .74,selected and .77 or .70,selected and .28 or .62)
            love.graphics.printf(row.label,300,row.y-36,360,"center")
            local value=row.kind=="weapon" and title(session.weapon) or row.kind=="motion" and title(session.motion)
                or row.kind=="material" and title(session.material) or row.kind=="pattern" and title(session.targetPattern)
                or tostring(session.stageLength).." Seconds"
            love.graphics.setColor(1,.89,.68); love.graphics.printf(value,290,row.y-4,380,"center",0,row.kind=="weapon" and 1.16 or 1.08,row.kind=="weapon" and 1.16 or 1.08)
            drawButton("<",{x=218,y=row.y-21,w=62,h=46},true); drawButton(">",{x=680,y=row.y-21,w=62,h=46},true)
        end
        local offer=Range.ammoOffer(session,catalog)
        local scrap=math.max(0,math.floor(tonumber(data.scrap) or 0))
        love.graphics.setColor(.78,.77,.70)
        local status=durability<=0 and "BROKEN - REPAIR IN THE TRAIN WORKSHOP"
            or combat.ammo and (string.upper(combat.ammo).." AVAILABLE: "..reserve) or "REUSABLE PROJECTILE"
        love.graphics.printf(status.."  |  SCRAP: "..scrap,250,497,460,"center",0,.84,.84)
        love.graphics.printf("SCORE MULTIPLIER x"..string.format("%.2f",Range.scoreMultiplier(session)),300,518,360,"center",0,.78,.78)
        local ammoLabel=offer and ("BUY "..offer.amount.." "..string.upper(offer.ammo).." - "..offer.cost.." SCRAP  [B]") or "NO AMMO NEEDED"
        drawButton(ammoLabel,{x=185,y=542,w=290,h=54},offer~=nil and scrap>=offer.cost)
        drawButton("START COURSE",{x=500,y=542,w=275,h=54},weaponReady(data,catalog,session.weapon))
        drawButton("LEAVE",{x=800,y=654,w=130,h=42},true)
    else
        local result=session.result
        love.graphics.setColor(1,.86,.58); love.graphics.printf("ROUND COMPLETE",180,128,600,"center",0,1.45,1.45)
        love.graphics.setColor(1,.72,.24); love.graphics.printf(result.rank,220,210,520,"center",0,1.45,1.45)
        love.graphics.setColor(.92,.86,.72)
        love.graphics.printf("SCORE  "..result.score.."\nACCURACY  "..math.floor(result.accuracy*100+.5).."%\nHIGH SCORE  "..result.highScore,250,282,460,"center",0,1.18,1.18)
        local reward=result.gained>0 and ("GOODWILL +"..result.gained)
            or result.rewardTier==0 and "HIT A TARGET TO EARN GOODWILL"
            or result.earnedRewardTier<result.rewardTier and ("GOODWILL BEST TIER +"..result.rewardTier)
            or "GOODWILL TIER ALREADY EARNED"
        love.graphics.setColor(.52,1,.57); love.graphics.printf(reward,230,420,500,"center")
        love.graphics.setColor(.82,.78,.68); love.graphics.printf(string.upper(session.motion).."  •  "..string.upper(session.material)
            .."  •  "..string.upper(session.targetPattern).."  •  "..session.stageLength.." SEC  •  SCORE x"..string.format("%.2f",Range.scoreMultiplier(session)),220,474,520,"center",0,.88,.88)
        drawButton("REPLAY",{x=238,y=548,w=150,h=58},weaponReady(data,catalog,session.weapon))
        drawButton("SETUP",{x=405,y=548,w=150,h=58},true)
        drawButton("DONE",{x=572,y=548,w=150,h=58},true)
    end
    if session.message then
        love.graphics.setColor(1,.42,.28)
        love.graphics.printf(session.message,220,session.phase=="lobby" and 610 or 500,520,"center")
    end
end

function Range.drawSpot(spot,image,clock)
    if not spot then return end
    local bob=math.sin((clock or 0)*1.5)*1.2
    if image then
        local scale=112/math.max(image:getWidth(),image:getHeight())
        love.graphics.setColor(1,1,1); love.graphics.draw(image,spot.x,spot.y+bob,0,scale,scale,image:getWidth()/2,image:getHeight())
    else
        love.graphics.setLineWidth(2)
        love.graphics.setColor(.24,.13,.065,1); love.graphics.line(spot.x,spot.y-2,spot.x,spot.y-30)
        love.graphics.setColor(.78,.07,.045,1)
        love.graphics.polygon("fill",spot.x+1,spot.y-29,spot.x+17,spot.y-24,spot.x+1,spot.y-18)
        love.graphics.setColor(.12,.065,.03,.42); love.graphics.ellipse("fill",spot.x,spot.y,7,3)
        love.graphics.setLineWidth(1)
    end
end

local TRAIL_FLAG_FRAMES={
    {column=0,row=0,anchorX=354,anchorY=552,height=353},
    {column=1,row=0,anchorX=295.5,anchorY=552,height=353},
    {column=1,row=1,anchorX=293,anchorY=456,height=357},
    {column=0,row=1,anchorX=322.5,anchorY=456,height=357},
}
local trailFlagQuadCache=setmetatable({},{__mode="k"})

local function animatedTrailFlagQuads(image)
    local cached=trailFlagQuadCache[image]
    if cached then return cached end
    local width,height=image:getDimensions()
    local cellWidth,cellHeight=width/2,height/2
    cached={cellWidth=cellWidth,cellHeight=cellHeight,quads={}}
    for index,frame in ipairs(TRAIL_FLAG_FRAMES) do
        cached.quads[index]=love.graphics.newQuad(frame.column*cellWidth,frame.row*cellHeight,cellWidth,cellHeight,width,height)
    end
    trailFlagQuadCache[image]=cached
    return cached
end

local function drawAnimatedTrailFlag(spot,image,clock)
    if not spot or not image then return end
    local frameIndex=math.floor((clock or 0)*5)%#TRAIL_FLAG_FRAMES+1
    local frame=TRAIL_FLAG_FRAMES[frameIndex]
    local cached=animatedTrailFlagQuads(image)
    local scale=34/frame.height
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,cached.quads[frameIndex],spot.x,spot.y,0,scale,scale,frame.anchorX,frame.anchorY)
end

Range.drawSpot=drawAnimatedTrailFlag

function Range.audit(catalog)
    local data={location=2,equipment={"trail-slingshot","hunting-bow","scrap-boomerang"},inventory={},ammo={rocks=3,arrows=0},weaponDurability={},scrap=5,goodwill=0,helpHistory={}}
    local spot={version=Range.version,x=760,y=565,rewarded=false,highScores={}}
    local session=assert(Range.new(data,spot,catalog,{npc="range-host.png"}))
    Range.changeSetup(session,data,catalog,"motion",1); Range.changeSetup(session,data,catalog,"material",1)
    Range.changeSetup(session,data,catalog,"pattern",1); Range.changeSetup(session,data,catalog,"length",1)
    local configured=session.motion=="moving" and session.material=="steel" and session.targetPattern=="pop-up" and session.stageLength==60
    local movingMultiplier=Range.scoreMultiplier(session)
    local offer=Range.ammoOffer(session,catalog); local purchased=Range.buyAmmo(session,data,catalog)
    resetRound(session,data,catalog); local stageTime=session.time
    local setupReturned=Range.returnToSetup(session); resetRound(session,data,catalog); Range.setAim(session,true)
    local adsX=select(1,Range.sway(session,catalog)); Range.setAim(session,false); local hipX=select(1,Range.sway(session,catalog))
    session.score=700; session.shots=5; session.hits=3
    local fakeHelp={add=function(save,amount) save.goodwill=(save.goodwill or 0)+amount; return amount end}
    local result=Range.complete(session,data,spot,fakeHelp)
    local second=Range.new(data,spot,catalog,{npc="range-host.png"}); resetRound(second,data,catalog); second.score=900; second.shots=5; second.hits=4
    local replay=Range.complete(second,data,spot,fakeHelp)
    local sparseWeapons=Range.ownedWeapons({equipment={[2]="trail-slingshot"},inventory={[4]="hunting-bow"}},catalog)
    local broken=Range.new({location=2,equipment={[2]="trail-slingshot"},inventory={},ammo={rocks=3},weaponDurability={["trail-slingshot"]=0}},
        {version=Range.version,x=760,y=565,rewarded=false,highScores={}},catalog)
    local zeroSpot={version=Range.version,x=760,y=565,rewarded=false,highScores={}}
    local zero=assert(Range.new(data,zeroSpot,catalog,{npc="range-host.png"})); resetRound(zero,data,catalog)
    local zeroResult=Range.complete(zero,data,zeroSpot,fakeHelp)
    local soundAudit=SoundProfiles.audit(catalog)
    local calibration=FirstPersonWeaponManifest.calibrationSummary()
    return {ready=Range.isHost(2) and not Range.isHost(3) and result.gained==2 and replay.gained==0 and data.goodwill==2 and spot.highScores["trail-slingshot"]==900
            and configured and math.abs(adsX)<=math.abs(hipX) and #soundAudit.missing==0 and #sparseWeapons==2 and broken==nil
            and zeroResult.gained==0 and zeroSpot.rewarded==false and movingMultiplier==1.30
            and offer and purchased and data.scrap==4 and data.ammo.rocks==19 and stageTime==60 and setupReturned
            and calibration.calibrated==45 and calibration.provisional==0 and calibration.withoutAnchor==1,
        hostCount=#Range.hostStops,ownedWeapons=#session.weapons,goodwill=result.gained,replayGoodwill=replay.gained,
        sparseOwned=#sparseWeapons,brokenRejected=broken==nil,zeroGoodwill=zeroResult.gained,
        movingMultiplier=movingMultiplier,targetPattern=session.targetPattern,stageLength=stageTime,ammoPurchased=purchased,scrapAfterAmmo=data.scrap,
        calibratedViews=calibration.calibrated,provisionalViews=calibration.provisional,
        modes=#Range.motionModes,targetTypes=#Range.targetTypes,assignedSounds=soundAudit.assigned,version=Range.version}
end

return Range
