-- Saved, independent practice lanes. Leases and private aim stay outside saves.
local P=require('game.net.protocol')
local Players=require('game.coop_players')
local Catalog=require('game.catalog')
local Range=require('game.shooting_range')
local Manifest=require('game.first_person_weapon_manifest')
local State={VERSION=1,MAX_REVISION=1000000000}
local function number(n,low,high) return type(n)=='number' and n==n and n>=low and n<=high end
local function reference(v,prefix) return P.text(v,32) and v:match('^'..prefix..'[1-9]%d*$')~=nil end
local function contains(values,v) for _,entry in ipairs(values) do if entry==v then return true end end end
local function fields(names) local result={}; for name in names:gmatch('%S+') do result[name]=true end; return result end
local gunFields=fields('weapon itemId ammoType capacity loaded needsReload cooldown reloadTimer fireMode weaponAction '
    ..'weaponActionElapsed weaponReloadDuration tubeReloadTotalRounds tubeReloadRemaining tubeReloadCompleted '
    ..'tubeReloadRoundTimer weaponViewSequence weaponViewState weaponViewPlacement')
local sessionFields=fields('version entityId spotId location roundRevision phase weapons selected clock score shots hits '
    ..'targets dirtImpacts spawnIndex nextSpawn time message motion material targetPattern stageLength distance sectionsHit '
    ..'completed result weaponSessions')
for name in pairs(gunFields) do sessionFields[name]=true end
local function array(values,max,validator)
    if type(values)~='table' or #values>max then return false end
    local count=0
    for index,value in pairs(values) do
        if not P.integer(index,1,#values) or validator and not validator(value) then return false end
        count=count+1
    end
    return count==#values
end
local function gun(g)
    if not P.fields(g,gunFields) or not Catalog.weaponCombat[g.weapon] or Catalog.weaponCombat[g.weapon].kind~='ranged'
        or not reference(g.itemId,'i') or g.ammoType~=Catalog.weaponCombat[g.weapon].ammo
        or not P.integer(g.capacity,1,100) or g.capacity~=math.max(1,Catalog.weaponCombat[g.weapon].capacity or 1)
        or not P.integer(g.loaded,0,g.capacity) or type(g.needsReload)~='boolean'
        or not number(g.cooldown,0,60) or not number(g.reloadTimer,0,120)
        or not Manifest.fireModeValid(g.weapon,g.fireMode) and g.fireMode~='single' then return false end
    if g.weaponAction~=nil and g.weaponAction~='fire' and g.weaponAction~='reload' then return false end
    for _,key in ipairs({'weaponActionElapsed','weaponReloadDuration','tubeReloadRoundTimer'}) do
        if g[key]~=nil and not number(g[key],0,120) then return false end
    end
    for _,key in ipairs({'tubeReloadTotalRounds','tubeReloadRemaining','tubeReloadCompleted'}) do
        if g[key]~=nil and not P.integer(g[key],0,g.capacity) then return false end
    end
    if g.weaponViewState~=nil and not P.text(g.weaponViewState,32) then return false end
    if g.weaponViewPlacement~=nil and g.weaponViewPlacement~='hip' and g.weaponViewPlacement~='sights' then return false end
    local seq=g.weaponViewSequence
    if seq then
        local definition=Manifest.shotSequenceFor(g.weapon)
        if not definition or not P.fields(seq,{index=true,elapsed=true}) or not P.integer(seq.index,1,#definition.steps)
            or not number(seq.elapsed,0,120) then return false end
    end
    return true
end
local impactFields=fields('offsetX offsetY variant material')
local targetFields=fields('id entityId x y baseX scale material sprite radius points life permanent age velocity hit impacts sections breaking clearing')
local function target(t)
    if not P.fields(t,targetFields) or not P.integer(t.id,1,1000000)
        or t.entityId~=nil and not reference(t.entityId,'e')
        or not contains(Range.targetTypes,t.material) or not P.integer(t.sprite,1,12)
        or not number(t.x,-1000,2000) or not number(t.y,-1000,2000) or not number(t.baseX,0,960)
        or not number(t.scale,.001,10) or not number(t.radius,.001,1000) or not P.integer(t.points,0,1000)
        or not number(t.life,0,120) or type(t.permanent)~='boolean' or not number(t.age,0,120)
        or not number(t.velocity,-1000,1000) or type(t.hit)~='boolean' then return false end
    if t.breaking~=nil and not number(t.breaking,0,120) then return false end
    if t.clearing~=nil and type(t.clearing)~='boolean' then return false end
    if not array(t.impacts,16,function(i) return P.fields(i,impactFields) and number(i.offsetX,-1000,1000)
        and number(i.offsetY,-1000,1000) and P.integer(i.variant,1,4) and (i.material=='paper' or i.material=='steel') end) then return false end
    if t.sections~=nil then
        if t.material~='sectioned' or type(t.sections)~='table' then return false end
        for index,s in pairs(t.sections) do
            if not P.integer(index,1,13) or not P.fields(s,{hit=true,breaking=true,broken=true,breakElapsed=true,impactX=true,impactY=true})
                or type(s.hit)~='boolean' or s.breaking~=nil and type(s.breaking)~='boolean'
                or s.broken~=nil and type(s.broken)~='boolean' or not number(s.breakElapsed,0,120)
                or not number(s.impactX,-1000,2000) or not number(s.impactY,-1000,2000) then return false end
        end
    end
    return true
end
local resultFields=fields('score accuracy rank gained rewardTier earnedRewardTier highScore newBest')
function State.validateSession(s)
    if not P.fields(s,sessionFields) or s.version~=State.VERSION or not reference(s.spotId,'e')
        or s.entityId~=nil and not reference(s.entityId,'e') or not P.integer(s.location,1,1000)
        or not P.integer(s.roundRevision,1,State.MAX_REVISION) or s.phase~='lobby' and s.phase~='play' and s.phase~='results'
        or not gun((function() local g={}; for key in pairs(gunFields) do g[key]=s[key] end; return g end)()) then return false end
    if not array(s.weapons,64,function(id) return reference(id,'i') end) or not P.integer(s.selected,1,#s.weapons)
        or s.weapons[s.selected]~=s.itemId then return false end
    if not contains(Range.motionModes,s.motion) or not contains(Range.targetTypes,s.material)
        or s.targetPattern~='stay-up' and s.targetPattern~='pop-up' or not contains(Range.stageLengths,s.stageLength)
        or not contains(Range.targetDistances,s.distance) then return false end
    if not number(s.clock,0,120) or not number(s.time,0,90) or not number(s.nextSpawn,-120,120)
        or not P.integer(s.spawnIndex,0,1000000) or not P.integer(s.score,0,100000000)
        or not P.integer(s.shots,0,1000000) or not P.integer(s.hits,0,s.shots*7)
        or not P.integer(s.sectionsHit,0,s.shots*7) or s.completed~=nil and type(s.completed)~='boolean'
        or s.message~=nil and not P.text(s.message,128) then return false end
    local ids={}
    if not array(s.targets,4,function(t)
        if not target(t) or t.id>s.spawnIndex or ids[t.id] then return false end; ids[t.id]=true; return true
    end) then return false end
    if not array(s.dirtImpacts,8,function(i)
        return P.fields(i,fields('x y variant age duration size lift')) and number(i.x,-1000,2000) and number(i.y,-1000,2000)
            and i.variant==5 and number(i.age,0,2) and number(i.duration,.01,2) and number(i.size,0,1000) and number(i.lift,0,1000)
    end) then return false end
    if type(s.weaponSessions)~='table' then return false end
    local count=0
    for id,g in pairs(s.weaponSessions) do count=count+1; if count>64 or not gun(g) or id~=g.itemId then return false end end
    local current=s.weaponSessions[s.itemId]
    if not current or current.weapon~=s.weapon or current.itemId~=s.itemId then return false end
    local r=s.result
    if r then
        if s.phase=='play' or not P.fields(r,resultFields) or not P.integer(r.score,0,100000000) or r.score~=s.score
            or not number(r.accuracy,0,7) or not contains({'SHARPSHOOTER','MARKSMOUSE','TRAIL HAND','BEGINNER'},r.rank)
            or not P.integer(r.gained,0,3) or not P.integer(r.rewardTier,0,3) or not P.integer(r.earnedRewardTier,0,3)
            or not P.integer(r.highScore,r.score,100000000) or type(r.newBest)~='boolean' then return false end
    elseif s.phase=='results' then return false end
    return true
end
function State.validate(data)
    local sessions=data.rangeSessions; if sessions==nil then return true end
    if not P.fields(sessions,{version=true,host=true,companion=true}) or sessions.version~=State.VERSION then return false end
    for _,id in ipairs({'host','companion'}) do
        if sessions[id] and (not Players.get(data,id) or not State.validateSession(sessions[id])) then return false end
    end
    return sessions.host~=sessions.companion or sessions.host==nil
end
function State.ensure(data)
    if not data.rangeSessions then data.rangeSessions={version=State.VERSION} end
    assert(State.validate(data),'invalid range sessions'); return data.rangeSessions
end
function State.session(data,id) local sessions=Players.campaignOf(data).rangeSessions; return sessions and sessions[id] end
function State.resource(spotId,id) return 'range:'..spotId..':'..id end
function State.scopes(data,id,spotId,command,args)
    local scopes={'activity:'..State.resource(spotId,id),'player:'..id}
    if command=='range.ammo' then scopes[#scopes+1]='resources' end
    if command=='range.configure' and args and args.action=='complete' then
        scopes[#scopes+1]='entity:'..spotId; scopes[#scopes+1]='resources'
    end
    return scopes
end
function State.view(data,id)
    local session=State.session(data,id); if not session then return nil end
    local function copy(value) if type(value)~='table' then return value end; local t={}; for k,v in pairs(value) do t[k]=copy(v) end; return t end
    local view=copy(session); view.weaponSessions=nil; return view
end
return State
