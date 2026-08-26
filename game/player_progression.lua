local Progression={}

Progression.maxLevel=12
Progression.healthPerLevel=3
Progression.abilityKinds={"heal","rally","protect","snare","sleep","paralyze","area","nourish","repair","haste","disarm","volley"}

function Progression.requirement(level)
    level=math.max(1,math.min(Progression.maxLevel-1,math.floor(level or 1)))
    local step=level-1
    return 10+6*step+2*step*step
end

function Progression.newStats()
    return {level=1,xp=0,nextXP=Progression.requirement(1)}
end

function Progression.ensure(data)
    data.stats=data.stats or Progression.newStats()
    data.stats.level=math.max(1,math.min(Progression.maxLevel,math.floor(tonumber(data.stats.level) or 1)))
    data.stats.xp=math.max(0,math.floor(tonumber(data.stats.xp) or 0))
    if data.stats.level>=Progression.maxLevel then data.stats.xp=0; data.stats.nextXP=0
    else data.stats.nextXP=Progression.requirement(data.stats.level) end
    return data.stats
end

function Progression.gainExperience(data,amount)
    local stats=Progression.ensure(data)
    if stats.level>=Progression.maxLevel then return 0 end
    stats.xp=stats.xp+math.max(0,math.floor(tonumber(amount) or 0))
    local levels=0
    while stats.level<Progression.maxLevel and stats.xp>=Progression.requirement(stats.level) do
        stats.xp=stats.xp-Progression.requirement(stats.level)
        stats.level=stats.level+1
        data.maxHealth=(data.maxHealth or 20)+Progression.healthPerLevel
        data.health=data.maxHealth
        levels=levels+1
    end
    if stats.level>=Progression.maxLevel then stats.xp=0; stats.nextXP=0
    else stats.nextXP=Progression.requirement(stats.level) end
    return levels
end

function Progression.combatBonuses(level)
    level=math.max(1,math.min(Progression.maxLevel,math.floor(level or 1)))
    return {
        attack=math.floor((level-1)/2),
        armor=math.floor((level-1)/4),
        move=math.floor((level-1)/6),
    }
end

function Progression.abilityRank(level)
    level=math.max(1,math.min(Progression.maxLevel,math.floor(level or 1)))
    return math.min(4,1+math.floor((level-1)/3))
end

function Progression.abilityProfile(kind,level)
    local rank=Progression.abilityRank(level); local profile={kind=kind,rank=rank,radius=2,rounds=2}
    if kind=="heal" then profile.heal=3+rank; profile.description="Restore "..profile.heal.." HP to nearby allies."
    elseif kind=="rally" then profile.aim=1+math.ceil(rank/2); profile.move=1+math.ceil(rank/2); profile.description="Nearby allies gain +"..profile.aim.." aim and +"..profile.move.." move."
    elseif kind=="protect" then profile.armor=1+rank; profile.description="Nearby allies gain +"..profile.armor.." armor."
    elseif kind=="snare" then profile.movePenalty=1+math.floor((rank-1)/2); profile.rounds=2+math.floor((rank-1)/2); profile.description="Reduce the nearest enemy's move by "..profile.movePenalty.." for "..profile.rounds.." rounds."
    elseif kind=="sleep" then profile.statusRounds=1+rank; profile.description="Put the nearest enemy to sleep for "..profile.statusRounds.." rounds."
    elseif kind=="paralyze" then profile.statusRounds=math.min(2,rank); profile.description="Paralyze the nearest enemy for "..profile.statusRounds.." round"..(profile.statusRounds==1 and "." or "s.")
    elseif kind=="area" then profile.damage=3+rank; profile.description="Deal "..profile.damage.." damage to nearby enemies."
    elseif kind=="nourish" then profile.heal=1+rank; profile.move=1+math.floor(rank/2); profile.description="Nearby allies heal "..profile.heal.." HP and gain +"..profile.move.." move."
    elseif kind=="repair" then profile.heal=1+rank; profile.armor=1+rank; profile.description="Nearby allies heal "..profile.heal.." HP and gain +"..profile.armor.." armor."
    elseif kind=="haste" then profile.aim=math.ceil(rank/2); profile.move=1+rank; profile.description="Nearby allies gain +"..profile.aim.." aim and +"..profile.move.." move."
    elseif kind=="disarm" then profile.aimPenalty=1+rank; profile.description="Reduce the nearest enemy's aim by "..profile.aimPenalty.."."
    elseif kind=="volley" then profile.damage=4+rank; profile.description="Strike the nearest enemy for "..profile.damage.." damage."
    else profile.description="Use this character's special ability." end
    return profile
end

function Progression.status(data)
    local stats=Progression.ensure(data); local bonuses=Progression.combatBonuses(stats.level)
    return {level=stats.level,xp=stats.xp,nextXP=stats.nextXP,maximum=stats.level>=Progression.maxLevel,
        abilityRank=Progression.abilityRank(stats.level),bonuses=bonuses}
end

function Progression.audit()
    local cumulative,requirements,strict=0,{},true; local previous=0
    for level=1,Progression.maxLevel-1 do
        local required=Progression.requirement(level); requirements[level]=required; cumulative=cumulative+required
        strict=strict and required>previous; previous=required
    end
    local sample={stats=Progression.newStats(),health=20,maxHealth=20}
    local gained=Progression.gainExperience(sample,58)
    local capped={stats=Progression.newStats(),health=20,maxHealth=20}; Progression.gainExperience(capped,99999)
    local baseProfiles,strongProfiles={},{}; local profilesReady=true
    for _,kind in ipairs(Progression.abilityKinds) do
        baseProfiles[kind]=Progression.abilityProfile(kind,1); strongProfiles[kind]=Progression.abilityProfile(kind,10)
        profilesReady=profilesReady and baseProfiles[kind].rank==1 and strongProfiles[kind].rank==4 and strongProfiles[kind].description~=baseProfiles[kind].description
    end
    local finalBonuses=Progression.combatBonuses(Progression.maxLevel)
    local ready=strict and cumulative==1210 and gained==3 and sample.stats.level==4 and sample.maxHealth==29 and sample.stats.nextXP==46
        and capped.stats.level==Progression.maxLevel and capped.stats.nextXP==0 and capped.stats.xp==0
        and Progression.abilityRank(1)==1 and Progression.abilityRank(4)==2 and Progression.abilityRank(7)==3 and Progression.abilityRank(10)==4
        and finalBonuses.attack==5 and finalBonuses.armor==2 and finalBonuses.move==1 and profilesReady
    return {ready=ready,maxLevel=Progression.maxLevel,requirements=requirements,cumulativeXP=cumulative,
        sampleLevel=sample.stats.level,sampleHealth=sample.maxHealth,sampleNextXP=sample.stats.nextXP,cappedLevel=capped.stats.level,
        finalBonuses=finalBonuses,abilityCount=#Progression.abilityKinds,baseProfiles=baseProfiles,strongProfiles=strongProfiles,curve="player-v2"}
end

return Progression
