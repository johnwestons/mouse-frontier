local LootProgression=require("game.loot_progression")
local RoamingMobs = {}

local function distance(ax,ay,bx,by)
    local dx,dy=bx-ax,by-ay
    return math.sqrt(dx*dx+dy*dy),dx,dy
end

local function meleeWeapon(ctx)
    local broken=false
    for i=1,2 do
        local name=ctx.data and ctx.data.equipment and ctx.data.equipment[i]
        local combat=name and ctx.catalog.weaponCombat and ctx.catalog.weaponCombat[name]
        if name and name~="scratch" and ctx.isWeapon(name) and (not combat or combat.kind~="ranged") then
            local condition=LootProgression.weaponCondition(ctx.data.weaponDurability and ctx.data.weaponDurability[name])
            if condition.multiplier>0 then return name,condition end
            broken=true
        end
    end
    return nil,nil,broken and "Your melee weapon is broken. Repair it at the train workshop." or "A melee weapon is required."
end

local function isActive(ctx,definition)
    return not ctx.isActive or ctx.isActive(definition)
end

local function canReach(ctx,x1,y1,x2,y2)
    return not ctx.canReach or ctx.canReach(x1,y1,x2,y2)
end

local function message(sys,text,duration)
    sys.message=text; sys.messageTimer=duration or 1.6
end

function RoamingMobs.new()
    return {transient={},attackTimer=0,message=nil,messageTimer=0}
end

local function transientFor(sys,areaId,mobId)
    sys.transient[areaId]=sys.transient[areaId] or {}
    local value=sys.transient[areaId][mobId]
    if not value then
        value={state="patrol",timer=0,patrolIndex=1,facing=1,animationDistance=0,hitTimer=0,healthTimer=0,deathTimer=0}
        sys.transient[areaId][mobId]=value
    end
    return value
end

local function moveToward(ctx,saved,transient,targetX,targetY,speed,dt)
    local goalDistance=distance(saved.x,saved.y,targetX,targetY)
    if goalDistance<2 then return true end
    if ctx.pathTarget then
        targetX,targetY=ctx.pathTarget(saved,targetX,targetY)
        if not targetX or not targetY then return false end
    end
    local d,dx,dy=distance(saved.x,saved.y,targetX,targetY)
    if d<1 then return false end
    local step=math.min(d,speed*dt)
    local oldX,oldY=saved.x,saved.y
    local newX,newY=oldX+dx/d*step,oldY+dy/d*step
    saved.x,saved.y=ctx.move(oldX,oldY,newX,newY)
    local moved=distance(oldX,oldY,saved.x,saved.y)
    transient.animationDistance=(transient.animationDistance or 0)+moved
    if math.abs(saved.x-oldX)>.05 then transient.facing=saved.x>oldX and 1 or -1 end
    return goalDistance<=2
end

local function alertPack(sys,ctx,definition)
    if not definition.packId then return end
    for _,other in ipairs(ctx.area.mobs or {}) do
        if other.packId==definition.packId and isActive(ctx,other) then
            local saved=ctx.areaState.mobs[other.id]
            if saved and not saved.dead then
                local d=distance(saved.x,saved.y,ctx.player.x,ctx.player.y)
                if d<=280 and canReach(ctx,saved.x,saved.y,ctx.player.x,ctx.player.y) then
                    local transient=transientFor(sys,ctx.area.id,other.id)
                    if transient.state=="patrol" then transient.state="alert"; transient.timer=.32 end
                end
            end
        end
    end
end

local function participants(sys,ctx,striker)
    local result={}
    for _,definition in ipairs(ctx.area.mobs or {}) do
        local saved=ctx.areaState.mobs[definition.id]
        local transient=transientFor(sys,ctx.area.id,definition.id)
        local active=definition.id==striker.id or transient.state=="alert" or transient.state=="chase" or transient.state=="windup" or transient.state=="recover" or transient.state=="stagger"
        local d=saved and distance(saved.x,saved.y,ctx.player.x,ctx.player.y) or math.huge
        if saved and not saved.dead and isActive(ctx,definition) and active and d<=330
            and canReach(ctx,saved.x,saved.y,ctx.player.x,ctx.player.y) then
            result[#result+1]={mobId=definition.id,file=definition.file,name=definition.name,hp=saved.hp,maxHp=saved.maxHp,
                tier=definition.tier,boss=definition.boss==true,weapon="mob-claw"}
        end
    end
    table.sort(result,function(a,b) return (a.mobId==striker.id and 0 or 1)<(b.mobId==striker.id and 0 or 1) end)
    return result
end

local function beginBattle(sys,ctx,striker)
    local enemyStates=participants(sys,ctx,striker)
    if #enemyStates==0 then return false end
    local mobFiles={}
    local boss=false
    for i,state in ipairs(enemyStates) do mobFiles[i]=state.file; boss=boss or state.boss end
    ctx.beginEncounter({
        source="expedition",areaId=ctx.area.id,tier=striker.tier,boss=boss,mobFiles=mobFiles,enemyStates=enemyStates,
        returnContext={scene="expedition",areaId=ctx.area.id,x=ctx.player.x,y=ctx.player.y},
    })
    return true
end

function RoamingMobs.update(sys,ctx,dt)
    sys.attackTimer=math.max(0,(sys.attackTimer or 0)-dt)
    sys.messageTimer=math.max(0,(sys.messageTimer or 0)-dt)
    for _,definition in ipairs(ctx.area.mobs or {}) do
        local saved=ctx.areaState.mobs[definition.id]
        local transient=transientFor(sys,ctx.area.id,definition.id)
        transient.hitTimer=math.max(0,(transient.hitTimer or 0)-dt)
        transient.healthTimer=math.max(0,(transient.healthTimer or 0)-dt)
        transient.staggerCooldown=math.max(0,(transient.staggerCooldown or 0)-dt)
        if not saved or not isActive(ctx,definition) then
            transient.state="patrol"; transient.timer=0
        elseif saved.dead then
            transient.deathTimer=(transient.deathTimer or 0)+dt
        elseif not ctx.grace then
            local awareness=definition.awareness or 185
            local reach=definition.reach or 82
            local speed=definition.speed or 62
            local d=distance(saved.x,saved.y,ctx.player.x,ctx.player.y)
            if transient.state=="patrol" then
                if d<=awareness and canReach(ctx,saved.x,saved.y,ctx.player.x,ctx.player.y) then
                    transient.state="alert"; transient.timer=.34; alertPack(sys,ctx,definition)
                else
                    local patrol=definition.patrol or {{x=definition.x,y=definition.y}}
                    local target=patrol[transient.patrolIndex] or patrol[1]
                    if moveToward(ctx,saved,transient,target.x,target.y,speed*.45,dt) then
                        transient.patrolIndex=transient.patrolIndex%#patrol+1
                    end
                end
            elseif transient.state=="alert" then
                transient.timer=transient.timer-dt
                if math.abs(ctx.player.x-saved.x)>.05 then transient.facing=ctx.player.x>saved.x and 1 or -1 end
                if transient.timer<=0 then transient.state="chase" end
            elseif transient.state=="chase" then
                if d<=reach and canReach(ctx,saved.x,saved.y,ctx.player.x,ctx.player.y) then
                    transient.state="windup"; transient.timer=definition.boss and .62 or .46
                elseif d>390 then
                    transient.state="patrol"
                else
                    moveToward(ctx,saved,transient,ctx.player.x,ctx.player.y,speed,dt)
                end
            elseif transient.state=="windup" then
                transient.timer=transient.timer-dt
                if transient.timer<=0 then
                    local hitDistance=distance(saved.x,saved.y,ctx.player.x,ctx.player.y)
                    if hitDistance<=reach+(definition.boss and 20 or 8)
                        and canReach(ctx,saved.x,saved.y,ctx.player.x,ctx.player.y)
                        and beginBattle(sys,ctx,definition) then return "battle" end
                    transient.state="recover"; transient.timer=definition.boss and .72 or .58
                end
            elseif transient.state=="recover" then
                transient.timer=transient.timer-dt
                if transient.timer<=0 then transient.state="chase" end
            elseif transient.state=="stagger" then
                transient.timer=transient.timer-dt
                if transient.timer<=0 then transient.state="chase" end
            end
        end
    end
end

function RoamingMobs.attack(sys,ctx,targetX,targetY)
    -- A repeated press is not a dialogue: it must never pause the cooldown.
    if sys.attackTimer>0 then return false end
    local weapon,condition,reason=meleeWeapon(ctx)
    if not weapon then message(sys,reason,2.4); return false,reason end
    local combat=ctx.catalog.weaponCombat[weapon] or {}
    local family=ctx.catalog.weaponFamily and ctx.catalog.weaponFamily(weapon) or combat.family or "melee"
    local reach=combat.fieldReach or math.max(100,math.min(180,30+(combat.range or 5)*20))
    local aimX,aimY=tonumber(targetX),tonumber(targetY)
    local explicit=aimX~=nil and aimY~=nil
    if not explicit then
        local intentX=tonumber(ctx.player.intentX) or ctx.player.facing or 1
        local intentY=tonumber(ctx.player.intentY) or 0
        if math.abs(intentX)+math.abs(intentY)<.001 then intentX=ctx.player.facing or 1 end
        aimX,aimY=ctx.player.x+intentX*100,ctx.player.y+intentY*100
    end
    local aimDistance,aimDX,aimDY=distance(ctx.player.x,ctx.player.y,aimX,aimY)
    if aimDistance<1 then aimDX,aimDY,aimDistance=ctx.player.facing or 1,0,1 end
    aimDX,aimDY=aimDX/aimDistance,aimDY/aimDistance
    if math.abs(aimDX)>.05 then ctx.player.facing=aimDX>=0 and 1 or -1 end
    local best,bestScore
    for _,definition in ipairs(ctx.area.mobs or {}) do
        local saved=ctx.areaState.mobs[definition.id]
        if saved and not saved.dead and isActive(ctx,definition) then
            local d,dx,dy=distance(ctx.player.x,ctx.player.y,saved.x,saved.y)
            local inArc=d<1 or (dx*aimDX+dy*aimDY)/d>=.5
            local clicked=explicit and math.abs(aimX-saved.x)<=(definition.boss and 60 or 36)
                and aimY>=saved.y-(definition.boss and 150 or 88) and aimY<=saved.y+10
            if d<=reach and (inArc or clicked) and canReach(ctx,ctx.player.x,ctx.player.y,saved.x,saved.y) then
                local groundClickDistance=distance(aimX,aimY,saved.x,saved.y)
                local bodyClickDistance=distance(aimX,aimY,saved.x,saved.y-(definition.boss and 60 or 35))
                local clickDistance=math.min(groundClickDistance,bodyClickDistance)
                -- A clicked sprite takes precedence over a nearer mob in the arc.
                local score=clicked and clickDistance-1000 or d
                if not bestScore or score<bestScore then best,bestScore=definition,score end
            end
        end
    end
    sys.attackTimer=({quick=.34,blunt=.50,axe=.48,polearm=.50})[family] or .42
    if ctx.onHostileAction then ctx.onHostileAction() end
    if ctx.onAction then ctx.onAction(weapon,sys.attackTimer) end
    if ctx.playSfx then ctx.playSfx("sword") end
    LootProgression.wearWeapon(ctx.data,weapon,1)
    ctx.data.weaponProficiency=ctx.data.weaponProficiency or {}
    local uses=(ctx.data.weaponProficiency[family] or ctx.data.weaponProficiency.melee or 0)+1
    ctx.data.weaponProficiency[family]=uses
    if not best then message(sys,"The swing misses.",1.2); return true end
    local saved=ctx.areaState.mobs[best.id]
    local transient=transientFor(sys,ctx.area.id,best.id)
    local stats=ctx.catalog.weaponStats[weapon] or {min=2,max=4}
    local proficiency=math.min(5,math.floor(uses/10))
    local damage=math.max(1,math.floor((love.math.random(stats.min or 2,stats.max or 4)+proficiency)*condition.multiplier))
    local remaining=saved.hp-damage
    -- The prototype's guardian always crosses into the authored boss battle.
    -- Field attacks can soften it to 1 HP but cannot bypass that encounter.
    saved.hp=best.boss and math.max(1,remaining) or math.max(0,remaining)
    transient.hitTimer=.38; transient.healthTimer=3
    -- Damage feedback never cancels an attack already committed to its windup.
    -- Blunt impacts can briefly check a pursuer, at most once per 1.5 seconds.
    if transient.state=="patrol" or transient.state=="alert" then transient.state="chase"; transient.timer=0 end
    if combat.status=="stagger" and not best.boss and transient.state=="chase" and (transient.staggerCooldown or 0)<=0 then
        transient.state="stagger"; transient.timer=.16; transient.staggerCooldown=1.5
    end
    alertPack(sys,ctx,best)
    if saved.hp<=0 then
        saved.dead=true; transient.deathTimer=0
        local rewardMessage=ctx.onDefeated and ctx.onDefeated(best,saved)
        sys.message=(best.name or "Enemy").." defeated!"..(type(rewardMessage)=="string" and " "..rewardMessage or "")
    elseif best.boss and remaining<=0 then
        sys.message="Its sludge shell breaks. Challenge the guardian to finish the battle!"
    else
        sys.message="Melee hit for "..damage.." damage."
    end
    sys.messageTimer=1.6
    return true
end

function RoamingMobs.challenge(sys,ctx,mobId)
    for _,definition in ipairs(ctx.area.mobs or {}) do
        if definition.id==mobId and definition.boss and isActive(ctx,definition) then
            local saved=ctx.areaState.mobs[mobId]
            if saved and not saved.dead and distance(saved.x,saved.y,ctx.player.x,ctx.player.y)<=180
                and canReach(ctx,saved.x,saved.y,ctx.player.x,ctx.player.y) then
                if ctx.onHostileAction then ctx.onHostileAction() end
                return beginBattle(sys,ctx,definition)
            end
        end
    end
    return false
end

local function actionFor(saved,transient,moving)
    if saved.dead then return 5 end
    if transient.state=="windup" then return 3 end
    if transient.hitTimer>0 or transient.state=="stagger" then return 4 end
    if transient.state=="alert" then return 6 end
    if moving and (transient.state=="chase" or transient.state=="patrol") then return 2 end
    return 1
end

function RoamingMobs.draw(sys,ctx,drawPlayer)
    local entries={}
    for _,definition in ipairs(ctx.area.mobs or {}) do
        local saved=ctx.areaState.mobs[definition.id]
        local transient=transientFor(sys,ctx.area.id,definition.id)
        if saved and (not saved.dead or transient.deathTimer<1.35) then entries[#entries+1]={definition=definition,saved=saved,transient=transient} end
    end
    table.sort(entries,function(a,b) return a.saved.y<b.saved.y end)
    local playerDrawn=not drawPlayer or not ctx.player
    for _,entry in ipairs(entries) do
        local definition,saved,transient=entry.definition,entry.saved,entry.transient
        if not playerDrawn and ctx.player.y<saved.y then
            love.graphics.setColor(1,1,1,1); drawPlayer(); playerDrawn=true
        end
        local travel=transient.animationDistance or 0
        local moving=transient.lastDrawDistance~=nil and math.abs(travel-transient.lastDrawDistance)>.001
        transient.lastDrawDistance=travel
        local action=actionFor(saved,transient,moving)
        local assets=ctx.assets[definition.file]
        local image=assets and assets[action]
        local anchor=assets and assets.anchors and assets.anchors.actions[action]
        if action==2 and assets and assets.walkFrames and #assets.walkFrames>0 then
            local frame=math.floor(travel/(assets.pixelsPerFrame or 8))%#assets.walkFrames+1
            image=assets.walkFrames[frame]
            anchor=assets.anchors and assets.anchors.walk[frame]
        end
        if image then
            local maxHeight=definition.boss and 155 or 88
            local scale=maxHeight/(assets.referenceHeight or image:getHeight())
            local alpha=saved.dead and math.max(0,1-transient.deathTimer/1.35) or 1
            love.graphics.setColor(0,0,0,.30*alpha)
            love.graphics.ellipse("fill",saved.x,saved.y+5,definition.boss and 48 or 25,definition.boss and 15 or 8)
            love.graphics.setColor(1,1,1,alpha)
            love.graphics.draw(image,saved.x,saved.y,0,scale*(transient.facing or 1)*(assets.baseFacing or 1),scale,
                anchor and anchor.x or image:getWidth()/2,anchor and anchor.y or image:getHeight())
            if not saved.dead and (transient.healthTimer>0 or transient.state~="patrol") then
                local width=definition.boss and 92 or 58
                love.graphics.setColor(.10,.025,.02,.90); love.graphics.rectangle("fill",saved.x-width/2,saved.y-maxHeight-12,width,8)
                love.graphics.setColor(definition.boss and .95 or .82,.14,.08,1)
                love.graphics.rectangle("fill",saved.x-width/2+1,saved.y-maxHeight-11,(width-2)*math.max(0,saved.hp/saved.maxHp),6)
            end
            if transient.state=="windup" and not saved.dead then
                local pulse=.5+.5*math.sin((ctx.clock or 0)*18)
                love.graphics.setColor(1,.18,.08,.55+.35*pulse)
                love.graphics.circle("line",saved.x,saved.y,(definition.reach or 82)+(definition.boss and 20 or 8))
            end
        end
    end
    if not playerDrawn then love.graphics.setColor(1,1,1,1); drawPlayer() end
end

function RoamingMobs.message(sys)
    if sys.messageTimer>0 then return sys.message end
end

function RoamingMobs.audit()
    return {ready=true,states={"patrol","alert","chase","windup","recover","stagger"},healthCarry=true,hitTriggered=true,curve="roaming-mobs-v2"}
end

return RoamingMobs
