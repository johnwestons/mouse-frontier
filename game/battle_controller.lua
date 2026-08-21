local Battle={}

local function armed(file)
    local s=(file or ""):lower()
    return s:find("cowboy",1,true) or s:find("marshal",1,true) or s:find("sheriff",1,true) or s:find("guard",1,true) or s:find("raider",1,true) or s:find("bandit",1,true)
end
local function natural(file)
    local s=(file or ""):lower()
    return (s:find("spit",1,true) or s:find("eagle",1,true) or s:find("owl",1,true) or s:find("dragon",1,true) or s:find("zombie",1,true)) and "mob-spit" or "mob-claw"
end
local function terrain()
    local n=love.math.random()
    if n<.55 then return 1 elseif n<.72 then return 2 elseif n<.88 then return 3 elseif n<.94 then return 5 elseif n<.985 then return 6 else return 4 end
end
local function msg(c,text) c.battle.message=text; c.battle.log=c.battle.log or {}; c.battle.log[#c.battle.log+1]=text; c.battle.logScroll=0 end
local function prompt(c,text) c.battle.message=text end
Battle.message=msg
Battle.prompt=prompt

function Battle.begin(c,encounter)
    encounter.mobFiles=encounter.mobFiles or (encounter.mobFile and {encounter.mobFile} or {})
    local tier=encounter.tier or (c.saveData.location<=4 and "easy" or (c.saveData.location<=8 and "medium" or "hard")); encounter.tier=tier
    local maxHP=encounter.maxHP or ({easy=12,medium=20,hard=32})[tier]; encounter.maxHP=maxHP
    local d=c.saveData; local C=c.Catalog; local units={{id="player",team="ally",name=c.Util.titleFromFile(d.character),file=d.character,q=1,r=2,hp=d.health,maxHP=d.maxHealth,move=2+(d.trait and d.trait.move or 0),armor=2+(d.trait and d.trait.armor or 0),aim=2+(d.trait and d.trait.combat or 0),controlled=true}}
    local starts={{q=1,r=3},{q=0,r=2},{q=0,r=4}}
    if encounter.temporaryAllies then
        for i,file in ipairs(encounter.temporaryAllies) do
            if i<=3 then
                local s=starts[i]
                units[#units+1]={id="defender"..i,team="ally",name=c.Util.titleFromFile(file),file=file,q=s.q,r=s.r,hp=14,maxHP=14,move=2,armor=1,aim=1,weapon=armed(file) and C.weaponProgression[math.min(#C.weaponProgression,math.max(1,1+math.floor((d.location-1)/3)))] or nil}
            end
        end
    else
        for i,p in ipairs(d.passengers or {}) do
            if i<=2 then
                local s=starts[i]
                units[#units+1]={id="ally"..i,team="ally",name=c.Util.titleFromFile(p.npc),file=p.npc,q=s.q,r=s.r,hp=12,maxHP=12,move=2,armor=1,aim=1,weapon=p.weapon}
            end
        end
    end
    local rows={1,2,3,4}; local armor=({easy=1,medium=3,hard=5})[tier]
    for i,file in ipairs(encounter.mobFiles) do
        local ranged=file:find("eagle") or file:find("owl") or file:find("dragon") or file:find("zombie")
        local isArmed=armed(file); local row=rows[((i-1)%#rows)+1]
        units[#units+1]={id="enemy"..i,team="enemy",name=c.Util.titleFromFile(file),file=file,q=c.BOARD_COLS,r=row,hp=maxHP,maxHP=maxHP,move=tier=="hard" and 3 or 2,armor=armor,aim=tier=="easy" and 0 or (tier=="medium" and 2 or 4),attackStyle=isArmed and "ranged" or (ranged and "ranged" or "melee"),weapon=isArmed and "frontier-9mm-service-pistol" or natural(file)}
    end
    local tiles,vars={},{ }
    for q=0,c.BOARD_COLS+1 do
        tiles[q]={}; vars[q]={}
        for r=1,c.BOARD_ROWS do
            tiles[q][r]=terrain(); vars[q][r]=love.math.random(1,2)
        end
    end
    tiles[c.BOARD_COLS+2]={}; vars[c.BOARD_COLS+2]={}
    for r=2,3 do
        tiles[c.BOARD_COLS+2][r]=terrain(); vars[c.BOARD_COLS+2][r]=love.math.random(1,2)
    end
    c.battle={encounter=encounter,units=units,tiles=tiles,tileVariants=vars,biome=((d.location-1)%4)+1,active=1,round=1,phase="select",selected=1,reachable={},message="Move between highlighted terrain pieces, or choose an attack.",log={"Battle begins."},logScroll=0,terrainSeed=d.location*19,attackTimer=0,hitFlash=0,intro=0,introDuration=1.65,abilitiesUsed={}}
    c.battleZoom=1; c.writeSave(); return c.battle
end

function Battle.advance(c)
    local b=c.battle; local enemy,ally=false,false; for _,u in ipairs(b.units) do if u.hp>0 then if u.team=="enemy" then enemy=true else ally=true end end end
    if not enemy then
        b.encounter.resolved=true; local d=c.saveData; local C=c.Catalog; if d.health<=0 then d.health=1; for _,unit in ipairs(b.units) do if unit.id=="player" then unit.hp=1 end end end
        local trait=d.trait or C.characterTraitProfiles[1]; local reward=love.math.random(3,6); local scrap=math.max(1,math.floor(love.math.random(4,8)*(trait.reward or 1)))+(trait.scrapBonus or 0); local xp=({easy=6,medium=12,hard=20})[b.encounter.tier or "easy"]; local defenseBonus=""
        if b.encounter.defenseBattle then reward=reward+4; scrap=scrap+8; xp=xp+8; d.resources.food=math.min(30,d.resources.food+2); d.resources.water=math.min(30,d.resources.water+2); defenseBonus=" The survivors share +2 food and +2 water." end
        local loot=c.Events.grantBattleLoot(d,C,b.encounter); local levels=c.BattleRules.gainExperience(d,xp); d.scrap=d.scrap+scrap; d.resources.coal=math.min(30,d.resources.coal+reward); msg(c,"Victory! +"..xp.." XP, +"..reward.." coal, +"..scrap.." scrap."..defenseBonus..loot..(levels>0 and " LEVEL UP!" or "")); b.finished="win"; c.writeSave(); return true
    end
    if not ally then c.saveData.health=math.max(1,math.floor(c.saveData.maxHealth/2)); msg(c,"Your party was overwhelmed and returned to the train."); b.finished="loss"; c.writeSave(); return true end
    c.BattleRules.endTurn(c.BattleRules.activeUnit(b)); local start=b.active; repeat b.active=b.active%#b.units+1 until b.units[b.active].hp>0 or b.active==start; if b.active==1 then b.round=b.round+1 end; b.units[b.active].guarding=false; b.phase="select"; b.selected=b.active; b.reachable={}; b.moveUsed=false; b.enemyDelay=b.units[b.active].team=="enemy" and .58 or 0
end

function Battle.attack(c,weapon)
    local b=c.battle; local u=c.BattleRules.activeUnit(b); if not u or u.team~="ally" or b.finished then return end; b.chosenWeapon=weapon; b.phase="target"; prompt(c,"Choose an enemy within "..c.BattleRules.weaponRange(c.Catalog,weapon).." terrain space(s).")
end
function Battle.move(c,q,r)
    local b=c.battle; local u=c.BattleRules.activeUnit(b); if not u or u.team~="ally" then return end
    if b.moveUsed or b.phase=="action" or b.phase=="target" then prompt(c,"Movement has already been used this turn."); return end
    if not c.BattleRules.isBoardSpace(b,q,r) or c.BattleRules.unitAt(b,q,r) or c.BattleRules.distance(u,{q=q,r=r})>u.move then prompt(c,"That terrain piece is outside this unit's movement range."); return end
    u.moveAnim={fromQ=u.q,fromR=u.r,toQ=q,toR=r,t=0,duration=.48}; u.q,u.r=q,r; b.moveUsed=true; b.phase="action"; prompt(c,u.name.." moved. Choose an attack or end the turn.")
end
function Battle.heal(c)
    local b=c.battle; local u=c.BattleRules.activeUnit(b); if not u or u.team~="ally" then return end
    for i=1,(c.saveData.inventoryCapacity or 6) do local name=c.saveData.inventory[i]; local effect=name and c.Catalog.itemEffects[name]; if effect and effect.health then u.action="use"; u.actionItem=name; u.actionTimer=.45; c.saveData.inventory[i]=nil; local before=u.hp; u.hp=math.min(u.maxHP,u.hp+effect.health); if u.id=="player" then c.saveData.health=u.hp end; msg(c,u.name.." recovered "..(u.hp-before).." HP."); Battle.advance(c); return end end
    prompt(c,"No healing item is available.")
end
function Battle.guard(c)
    local u=c.BattleRules.activeUnit(c.battle); if u and u.team=="ally" then u.guarding=true; msg(c,u.name.." braces behind cover."); Battle.advance(c) end
end
function Battle.ability(c,kind)
    local b=c.battle; local u=c.BattleRules.activeUnit(b); if not u or u.team~="ally" or b.abilitiesUsed[u.id] then return end; b.abilitiesUsed[u.id]=true
    if kind=="heal" then for _,a in ipairs(b.units) do if a.team=="ally" and a.hp>0 and c.BattleRules.distance(u,a)<=2 then a.hp=math.min(a.maxHP,a.hp+4); if a.id=="player" then c.saveData.health=a.hp end end end; msg(c,u.name.." restored nearby allies.")
    elseif kind=="rally" then for _,a in ipairs(b.units) do if a.team=="ally" and a.hp>0 and c.BattleRules.distance(u,a)<=2 then c.BattleRules.applyTemporaryStat(a,"aim",2,2); c.BattleRules.applyTemporaryStat(a,"move",2,2) end end; msg(c,u.name.." rallied nearby allies.")
    elseif kind=="protect" then for _,a in ipairs(b.units) do if a.team=="ally" and a.hp>0 and c.BattleRules.distance(u,a)<=2 then c.BattleRules.applyTemporaryStat(a,"armor",2,2) end end; msg(c,u.name.." fortified nearby allies.")
    elseif kind=="snare" or kind=="sleep" or kind=="paralyze" then local closest; for _,e in ipairs(b.units) do if e.team=="enemy" and e.hp>0 and (not closest or c.BattleRules.distance(u,e)<c.BattleRules.distance(u,closest)) then closest=e end end; if closest then if kind=="snare" then c.BattleRules.applyTemporaryStat(closest,"move",-1,2); msg(c,closest.name.." was ensnared and slowed.") elseif kind=="sleep" then closest.sleepRounds=2; msg(c,closest.name.." fell asleep.") else closest.paralyzedRounds=1; msg(c,closest.name.." was paralyzed.") end end
    elseif kind=="area" then local hits=0; for _,e in ipairs(b.units) do if e.team=="enemy" and e.hp>0 and c.BattleRules.distance(u,e)<=2 then e.hp=math.max(0,e.hp-4); e.hitTimer=.58; e.damageNumber=4; e.damageNumberTimer=.9; hits=hits+1 end end; msg(c,u.name.." struck "..hits.." nearby enem"..(hits==1 and "y." or "ies."))
    elseif kind=="nourish" then for _,a in ipairs(b.units) do if a.team=="ally" and a.hp>0 and c.BattleRules.distance(u,a)<=2 then a.hp=math.min(a.maxHP,a.hp+2); c.BattleRules.applyTemporaryStat(a,"move",1,2); if a.id=="player" then c.saveData.health=a.hp end end end; msg(c,u.name.." shared a nourishing meal.")
    elseif kind=="repair" then for _,a in ipairs(b.units) do if a.team=="ally" and a.hp>0 and c.BattleRules.distance(u,a)<=2 then a.hp=math.min(a.maxHP,a.hp+2); c.BattleRules.applyTemporaryStat(a,"armor",2,2); if a.id=="player" then c.saveData.health=a.hp end end end; msg(c,u.name.." repaired nearby allies.")
    elseif kind=="haste" then for _,a in ipairs(b.units) do if a.team=="ally" and a.hp>0 and c.BattleRules.distance(u,a)<=2 then c.BattleRules.applyTemporaryStat(a,"aim",1,2); c.BattleRules.applyTemporaryStat(a,"move",2,2) end end; msg(c,u.name.." got the party moving.")
    elseif kind=="disarm" then local closest; for _,e in ipairs(b.units) do if e.team=="enemy" and e.hp>0 and (not closest or c.BattleRules.distance(u,e)<c.BattleRules.distance(u,closest)) then closest=e end end; if closest then c.BattleRules.applyTemporaryStat(closest,"aim",-2,2); msg(c,closest.name.." was disarmed and weakened.") end
    elseif kind=="volley" then local closest; for _,e in ipairs(b.units) do if e.team=="enemy" and e.hp>0 and (not closest or c.BattleRules.distance(u,e)<c.BattleRules.distance(u,closest)) then closest=e end end; if closest then closest.hp=math.max(0,closest.hp-5); closest.hitTimer=.58; closest.damageNumber=5; closest.damageNumberTimer=.9; msg(c,u.name.." hit "..closest.name.." with a volley for 5 damage.") end end
    Battle.advance(c)
end
function Battle.resolve(c,attacker,target,weaponName)
    local b=c.battle; local C=c.Catalog; local d=c.saveData; local stats=C.weaponStats[weaponName] or C.weaponStats.scratch; local combat=C.weaponCombat[weaponName] or C.weaponCombat.scratch; local distance=c.BattleRules.distance(attacker,target); local range=c.BattleRules.weaponRange(C,weaponName)
    if distance>range then prompt(c,stats.name.." is out of range ("..range.." terrain spaces)."); return false end
    if combat.ammo and attacker.team=="ally" then local count=d.ammo[combat.ammo] or 0; if count<=0 then msg(c,attacker.name.." has no "..c.Util.titleFromFile(combat.ammo).." ammunition."); return false end; d.ammo[combat.ammo]=count-1 end
    attacker.action=combat.kind=="ranged" and "ranged" or "melee"; attacker.actionItem=weaponName; attacker.actionTimer=attacker.team=="enemy" and .68 or .45; c.playSfx(c.weaponSfx(weaponName,combat)); if combat.kind=="ranged" then b.projectile={fromQ=attacker.q,fromR=attacker.r,toQ=target.q,toR=target.r,ammo=combat.ammo or "rocks",weapon=weaponName,kind=combat.projectile,t=0,duration=attacker.team=="enemy" and .62 or .42} end
    local _,cover=c.BattleRules.terrainAt(b,target.q,target.r); local roll=love.math.random(1,20); local bonus=(attacker.aim or 0)+(attacker.id=="player" and math.floor((d.stats.level-1)/2) or 0); local defense=8+(target.armor or 0)+cover+(distance>1 and distance-1 or 0); local name=C.weaponStats[weaponName] and C.weaponStats[weaponName].name or c.Util.titleFromFile(weaponName)
    if roll==1 or (roll~=20 and roll+bonus<defense) then msg(c,attacker.name.." used "..name.." against "..target.name.." — MISS."); b.attackTimer=attacker.team=="enemy" and .90 or .45; Battle.advance(c); return true end
    local durability=attacker.team=="ally" and weaponName~="scratch" and (d.weaponDurability[weaponName] or 100) or 100; local condition=durability<25 and .70 or (durability<50 and .82 or (durability<75 and .92 or 1)); local prof=0
    if attacker.id=="player" then local family=C.weaponFamily(weaponName); local uses=(d.weaponProficiency[family] or 0)+1; d.weaponProficiency[family]=uses; prof=math.min(5,math.floor(uses/10)) end
    local raw=love.math.random(stats.min,stats.max)+(attacker.aim or 0)+prof+(roll==20 and 3 or 0); local damage=math.max(1,math.floor(raw*condition)-(target.armor or 0)); if target.guarding then damage=love.math.random()<.30 and 0 or math.max(1,math.floor(damage*.4)); target.guarding=false end
    target.hp=math.max(0,target.hp-damage); target.hitTimer=.58; target.damageNumber=damage; target.damageNumberTimer=.9; if target.id=="player" then d.health=target.hp end; if attacker.team=="ally" and weaponName~="scratch" then d.weaponDurability[weaponName]=math.max(0,durability-love.math.random(1,2)) end
    msg(c,attacker.name.." used "..name.." on "..target.name.." — HIT for "..damage.." damage."); b.attackTimer=attacker.team=="enemy" and .95 or .45; b.hitFlash=.18; b.lastTarget=target.id; Battle.advance(c); return true
end
function Battle.enemyTurn(c)
    local b=c.battle; local enemy=c.BattleRules.activeUnit(b); if not enemy or enemy.team~="enemy" or b.finished then return end
    if (enemy.sleepRounds or 0)>0 or (enemy.paralyzedRounds or 0)>0 then local status=(enemy.sleepRounds or 0)>0 and "asleep" or "paralyzed"; enemy.sleepRounds=math.max(0,(enemy.sleepRounds or 0)-1); enemy.paralyzedRounds=math.max(0,(enemy.paralyzedRounds or 0)-1); msg(c,enemy.name.." is "..status.." and loses its turn."); Battle.advance(c); return end
    local target; for _,u in ipairs(b.units) do if u.team=="ally" and u.hp>0 and (not target or c.BattleRules.distance(enemy,u)<c.BattleRules.distance(enemy,target)) then target=u end end; if not target then return end
    local weapon=enemy.weapon or (enemy.attackStyle=="ranged" and "mob-spit" or "mob-claw"); local preferred=enemy.attackStyle=="ranged" and c.BattleRules.weaponRange(c.Catalog,weapon) or 1
    if c.BattleRules.distance(enemy,target)>preferred then local q,r,d=enemy.q,enemy.r,c.BattleRules.distance(enemy,target); for _,dir in ipairs(c.BattleRules.directions) do local nq,nr=enemy.q+dir[1],enemy.r+dir[2]; local nd=c.BattleRules.distance({q=nq,r=nr},target); if c.BattleRules.isBoardSpace(b,nq,nr) and not c.BattleRules.unitAt(b,nq,nr) and nd<d then q,r,d=nq,nr,nd end end; if q~=enemy.q or r~=enemy.r then enemy.moveAnim={fromQ=enemy.q,fromR=enemy.r,toQ=q,toR=r,t=0,duration=.68} end; enemy.q,enemy.r=q,r; prompt(c,enemy.name.." advances across the battlefield."); b.attackTimer=.82; Battle.advance(c) else Battle.resolve(c,enemy,target,weapon) end
end
function Battle.update(c,dt)
    local b=c.battle; if not b then return end; b.attackTimer=math.max(0,(b.attackTimer or 0)-dt); b.enemyDelay=math.max(0,(b.enemyDelay or 0)-dt); b.hitFlash=math.max(0,(b.hitFlash or 0)-dt)
    if b.intro then b.intro=b.intro+dt; if b.intro>=b.introDuration then b.intro=nil end end
    local busy=false; for _,u in ipairs(b.units or {}) do u.actionTimer=math.max(0,(u.actionTimer or 0)-dt); u.hitTimer=math.max(0,(u.hitTimer or 0)-dt); u.damageNumberTimer=math.max(0,(u.damageNumberTimer or 0)-dt); if u.actionTimer<=0 then u.action=nil end; if u.moveAnim then u.moveAnim.t=u.moveAnim.t+dt; if u.moveAnim.t>=u.moveAnim.duration then u.moveAnim=nil end end; if u.actionTimer>0 or u.hitTimer>0 or u.moveAnim then busy=true end end
    if b.projectile then b.projectile.t=b.projectile.t+dt; if b.projectile.t>=b.projectile.duration then b.projectile=nil end end
    if b.projectile then busy=true end
    if not b.intro and not b.finished and not busy and b.attackTimer<=0 and b.enemyDelay<=0 then local u=c.BattleRules.activeUnit(b); if u and u.team=="enemy" then Battle.enemyTurn(c) end end
end
return Battle
