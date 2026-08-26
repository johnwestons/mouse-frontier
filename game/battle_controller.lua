local Battle={}
local LootProgression=require("game.loot_progression")

local function applyPotionToPlayer(c,unit,name)
    local effect=c.Catalog.itemEffects[name]
    if not effect or not effect.potion then return false end
    local d=c.saveData
    if effect.attack then unit.aim=(unit.aim or 0)+effect.attack end
    if effect.defense then unit.armor=(unit.armor or 0)+effect.defense end
    if effect.move then unit.move=(unit.move or 0)+effect.move end
    if effect.healthMax then unit.maxHP=(unit.maxHP or d.maxHealth)+effect.healthMax; unit.hp=math.min(unit.maxHP,(unit.hp or 0)+effect.health or 0) end
    if effect.extraAttacks then unit.extraAttacks=(unit.extraAttacks or 0)+effect.extraAttacks end
    if effect.extraMoves then unit.extraMoves=(unit.extraMoves or 0)+effect.extraMoves end
    if effect.guardAllies then for _,ally in ipairs(c.battle and c.battle.units or {}) do if ally.team=="ally" and ally.hp>0 then ally.guarding=true end end end
    if effect.perfectAccuracy then unit.perfectAccuracy=true end
    if effect.regenRounds then for _,ally in ipairs(c.battle and c.battle.units or {}) do if ally.team=="ally" and ally.hp>0 then ally.regenRounds=effect.regenRounds; ally.regenAmount=effect.regenAmount end end end
    if unit.id=="player" then d.health=unit.hp end
    if effect.rareLootChance then d.battlePotionLootChance=math.max(d.battlePotionLootChance or 0,effect.rareLootChance) end
    return true
end

local function armed(file)
    local s=(file or ""):lower()
    if s:find("mouse-bandit",1,true) then return false end
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
    local tier=encounter.tier or c.CombatBalance.tierFor(c.saveData.location); encounter.tier=tier
    local profile=c.CombatBalance.enemyProfile(c.saveData.location,tier)
    local maxHP=encounter.maxHP or profile.maxHP; encounter.maxHP=maxHP
    local d=c.saveData; local C=c.Catalog; local levelBonuses=c.PlayerProgression.combatBonuses(d.stats.level)
    local units={{id="player",team="ally",name=c.Util.titleFromFile(d.character),file=d.character,q=1,r=2,hp=d.health,maxHP=d.maxHealth,move=2+(d.trait and d.trait.move or 0)+levelBonuses.move,armor=2+(d.trait and d.trait.armor or 0)+levelBonuses.armor,aim=2+(d.trait and d.trait.combat or 0),controlled=true}}
    local starts={{q=1,r=3},{q=0,r=2},{q=0,r=4}}
    if encounter.temporaryAllies then
        for i,file in ipairs(encounter.temporaryAllies) do
            if i<=3 then
                local s=starts[i]
                units[#units+1]={id="defender"..i,team="ally",name=c.Util.titleFromFile(file),file=file,q=s.q,r=s.r,hp=14,maxHP=14,move=2,armor=1,aim=1,weapon=armed(file) and LootProgression.rollWeapon(C,d.location,"common") or nil}
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
    local rows={1,2,3,4}
    for i,file in ipairs(encounter.mobFiles) do
        local ranged=file:find("eagle") or file:find("owl") or file:find("dragon") or file:find("zombie")
        local isArmed=armed(file); local row=rows[((i-1)%#rows)+1]
        local weapon=isArmed and LootProgression.rollWeapon(C,d.location,"common") or natural(file)
        local combat=C.weaponCombat[weapon] or C.weaponCombat.scratch
        units[#units+1]={id="enemy"..i,team="enemy",name=c.Util.titleFromFile(file),file=file,q=c.BOARD_COLS,r=row,hp=maxHP,maxHP=maxHP,move=profile.move,armor=profile.armor,aim=profile.aim,attackStyle=combat.kind=="ranged" and "ranged" or "melee",weapon=weapon}
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
    for name in pairs(d.nextBattlePotions or {}) do applyPotionToPlayer(c,units[1],name) end
    d.nextBattlePotions={}; c.writeSave()
    c.battleZoom=1; c.writeSave(); return c.battle
end

function Battle.advance(c)
    local b=c.battle; local enemy,ally=false,false; for _,u in ipairs(b.units) do if u.hp>0 then if u.team=="enemy" then enemy=true else ally=true end end end
    if not enemy then
        b.encounter.resolved=true; local d=c.saveData; local C=c.Catalog; if d.health<=0 then d.health=1; for _,unit in ipairs(b.units) do if unit.id=="player" then unit.hp=1 end end end
        local enemyCount=0; for _,unit in ipairs(b.units) do if unit.team=="enemy" then enemyCount=enemyCount+1 end end
        local rewards=c.CombatBalance.rewardProfile(b.encounter.tier,enemyCount,b.encounter.defenseBattle)
        local trait=d.trait or C.characterTraitProfiles[1]; local reward=love.math.random(rewards.coalMin,rewards.coalMax); local scrap=math.max(1,math.floor(love.math.random(rewards.scrapMin,rewards.scrapMax)*(trait.reward or 1)))+(trait.scrapBonus or 0); local xp=rewards.xp; local defenseBonus=""
        if b.encounter.defenseBattle then local food=c.TrainUpgradeBalance.addResource(d,"food",2); local water=c.TrainUpgradeBalance.addResource(d,"water",2); defenseBonus=" The survivors share +"..food.." food and +"..water.." water." end
        local loot=c.Events.grantBattleLoot(d,C,b.encounter); local levels=c.BattleRules.gainExperience(d,xp); d.scrap=d.scrap+scrap; local coal=c.TrainUpgradeBalance.addResource(d,"coal",reward); d.battlePotionLootChance=nil; msg(c,"Victory! +"..xp.." XP, +"..coal.." coal, +"..scrap.." scrap."..defenseBonus..loot..(levels>0 and " LEVEL UP!" or "")); b.finished="win"; c.writeSave(); return true
    end
    if not ally then c.saveData.health=math.max(1,math.floor(c.saveData.maxHealth/2)); c.saveData.battlePotionLootChance=nil; msg(c,"Your party was overwhelmed and returned to the train."); b.finished="loss"; c.writeSave(); return true end
    local ended=c.BattleRules.activeUnit(b); c.BattleRules.endTurn(ended); ended.extraAttacks=nil; ended.extraMoves=nil; ended.perfectAccuracy=nil
    local start=b.active; repeat b.active=b.active%#b.units+1 until b.units[b.active].hp>0 or b.active==start; if b.active==1 then b.round=b.round+1 end
    local active=b.units[b.active]; active.guarding=false
    if active.team=="ally" and (active.regenRounds or 0)>0 then local healed=math.min(active.maxHP,active.hp+(active.regenAmount or 2))-active.hp; active.hp=active.hp+healed; active.regenRounds=active.regenRounds-1; if active.id=="player" then c.saveData.health=active.hp end; if healed>0 then msg(c,active.name.." regenerated "..healed.." HP.") end end
    b.phase="select"; b.selected=b.active; b.reachable={}; b.moveUsed=false; b.enemyDelay=active.team=="enemy" and .58 or 0
end

function Battle.usePotion(c,name)
    local b=c.battle; local active=c.BattleRules.activeUnit(b)
    if not active or active.team~="ally" or b.finished then return false end
    local player
    for _,unit in ipairs(b.units or {}) do if unit.id=="player" then player=unit; break end end
    if not player then return false end
    local found
    for i=1,(c.saveData.inventoryCapacity or 6) do if c.saveData.inventory[i]==name then found=i; break end end
    local effect=c.Catalog.itemEffects[name]
    if not found or not applyPotionToPlayer(c,player,name) then return false end
    c.saveData.inventory[found]=nil; player.action="use"; player.actionItem=name; player.actionTimer=.45
    if effect.extraMoves then b.moveUsed=false; b.phase="select" end
    if effect.battleAction then msg(c,player.name.." drank "..c.Util.titleFromFile(name).."."); c.writeSave(); return true end
    msg(c,player.name.." drank "..c.Util.titleFromFile(name).."."); Battle.advance(c); c.writeSave(); return true
end

function Battle.useHealingItem(c,name)
    local b=c.battle; local u=c.BattleRules.activeUnit(b)
    if not u or u.team~="ally" or b.finished then return false end
    local effect=c.Catalog.itemEffects[name]
    if not effect or not effect.health then return false end
    local slot
    for i=1,(c.saveData.inventoryCapacity or 6) do if c.saveData.inventory[i]==name then slot=i; break end end
    if not slot then return false end
    c.saveData.inventory[slot]=nil; u.action="use"; u.actionItem=name; u.actionTimer=.45
    local before=u.hp; u.hp=math.min(u.maxHP,u.hp+effect.health)
    if u.id=="player" then c.saveData.health=u.hp end
    msg(c,u.name.." used "..c.Util.titleFromFile(name).." and recovered "..(u.hp-before).." HP.")
    Battle.advance(c); c.writeSave(); return true
end

function Battle.attack(c,weapon)
    local b=c.battle; local u=c.BattleRules.activeUnit(b); if not u or u.team~="ally" or b.finished then return end; b.chosenWeapon=weapon; b.phase="target"; prompt(c,"Choose an enemy within "..c.BattleRules.weaponRange(c.Catalog,weapon).." terrain space(s).")
end
function Battle.move(c,q,r)
    local b=c.battle; local u=c.BattleRules.activeUnit(b); if not u or u.team~="ally" then return end
    if b.moveUsed or b.phase=="action" or b.phase=="target" then prompt(c,"Movement has already been used this turn."); return end
    if not c.BattleRules.isBoardSpace(b,q,r) or c.BattleRules.unitAt(b,q,r) or c.BattleRules.distance(u,{q=q,r=r})>u.move then prompt(c,"That terrain piece is outside this unit's movement range."); return end
    u.moveAnim={fromQ=u.q,fromR=u.r,toQ=q,toR=r,t=0,duration=.48}; u.q,u.r=q,r; b.moveUsed=true
    if u.id=="player" and (u.extraMoves or 0)>0 then u.extraMoves=u.extraMoves-1; b.moveUsed=false; b.phase="select"; prompt(c,u.name.." moved. One extra move remains.") else b.phase="action"; prompt(c,u.name.." moved. Choose an attack or end the turn.") end
end
function Battle.heal(c)
    local b=c.battle; local u=c.BattleRules.activeUnit(b); if not u or u.team~="ally" then return end
    for i=1,(c.saveData.inventoryCapacity or 6) do local name=c.saveData.inventory[i]; local effect=name and c.Catalog.itemEffects[name]; if effect and effect.health then u.action="use"; u.actionItem=name; u.actionTimer=.45; c.saveData.inventory[i]=nil; local before=u.hp; u.hp=math.min(u.maxHP,u.hp+effect.health); if u.id=="player" then c.saveData.health=u.hp end; msg(c,u.name.." recovered "..(u.hp-before).." HP."); Battle.advance(c); return end end
    prompt(c,"No healing item is available.")
end
function Battle.guard(c)
    local u=c.BattleRules.activeUnit(c.battle); if u and u.team=="ally" then u.guarding=true; msg(c,u.name.." braces behind cover."); Battle.advance(c) end
end

local function advanceAttack(c,attacker)
    local b=c.battle
    if attacker.id=="player" and (attacker.extraAttacks or 0)>0 then
        attacker.extraAttacks=attacker.extraAttacks-1
        local enemy=false; for _,unit in ipairs(b.units or {}) do if unit.team=="enemy" and unit.hp>0 then enemy=true; break end end
        if enemy then b.phase="select"; b.selected=b.active; b.reachable={}; prompt(c,attacker.name.." can attack again this turn."); return end
    end
    Battle.advance(c)
end
function Battle.ability(c,kind)
    local b=c.battle; local u=c.BattleRules.activeUnit(b); if not u or u.team~="ally" or b.abilitiesUsed[u.id] then return end; b.abilitiesUsed[u.id]=true
    local abilityLevel=u.id=="player" and c.saveData.stats.level or 1
    local profile=c.PlayerProgression.abilityProfile(kind,abilityLevel)
    if kind=="heal" then for _,a in ipairs(b.units) do if a.team=="ally" and a.hp>0 and c.BattleRules.distance(u,a)<=profile.radius then a.hp=math.min(a.maxHP,a.hp+profile.heal); if a.id=="player" then c.saveData.health=a.hp end end end; msg(c,u.name.." restored nearby allies with rank "..profile.rank.." healing.")
    elseif kind=="rally" then for _,a in ipairs(b.units) do if a.team=="ally" and a.hp>0 and c.BattleRules.distance(u,a)<=profile.radius then c.BattleRules.applyTemporaryStat(a,"aim",profile.aim,profile.rounds); c.BattleRules.applyTemporaryStat(a,"move",profile.move,profile.rounds) end end; msg(c,u.name.." rallied nearby allies.")
    elseif kind=="protect" then for _,a in ipairs(b.units) do if a.team=="ally" and a.hp>0 and c.BattleRules.distance(u,a)<=profile.radius then c.BattleRules.applyTemporaryStat(a,"armor",profile.armor,profile.rounds) end end; msg(c,u.name.." fortified nearby allies.")
    elseif kind=="snare" or kind=="sleep" or kind=="paralyze" then local closest; for _,e in ipairs(b.units) do if e.team=="enemy" and e.hp>0 and (not closest or c.BattleRules.distance(u,e)<c.BattleRules.distance(u,closest)) then closest=e end end; if closest then if kind=="snare" then c.BattleRules.applyTemporaryStat(closest,"move",-profile.movePenalty,profile.rounds); msg(c,closest.name.." was ensnared and slowed.") elseif kind=="sleep" then closest.sleepRounds=profile.statusRounds; msg(c,closest.name.." fell asleep.") else closest.paralyzedRounds=profile.statusRounds; msg(c,closest.name.." was paralyzed.") end end
    elseif kind=="area" then local hits=0; for _,e in ipairs(b.units) do if e.team=="enemy" and e.hp>0 and c.BattleRules.distance(u,e)<=profile.radius then e.hp=math.max(0,e.hp-profile.damage); e.hitTimer=.58; e.damageNumber=profile.damage; e.damageNumberTimer=.9; hits=hits+1 end end; msg(c,u.name.." struck "..hits.." nearby enem"..(hits==1 and "y" or "ies").." for "..profile.damage.." damage.")
    elseif kind=="nourish" then for _,a in ipairs(b.units) do if a.team=="ally" and a.hp>0 and c.BattleRules.distance(u,a)<=profile.radius then a.hp=math.min(a.maxHP,a.hp+profile.heal); c.BattleRules.applyTemporaryStat(a,"move",profile.move,profile.rounds); if a.id=="player" then c.saveData.health=a.hp end end end; msg(c,u.name.." shared a nourishing meal.")
    elseif kind=="repair" then for _,a in ipairs(b.units) do if a.team=="ally" and a.hp>0 and c.BattleRules.distance(u,a)<=profile.radius then a.hp=math.min(a.maxHP,a.hp+profile.heal); c.BattleRules.applyTemporaryStat(a,"armor",profile.armor,profile.rounds); if a.id=="player" then c.saveData.health=a.hp end end end; msg(c,u.name.." repaired nearby allies.")
    elseif kind=="haste" then for _,a in ipairs(b.units) do if a.team=="ally" and a.hp>0 and c.BattleRules.distance(u,a)<=profile.radius then c.BattleRules.applyTemporaryStat(a,"aim",profile.aim,profile.rounds); c.BattleRules.applyTemporaryStat(a,"move",profile.move,profile.rounds) end end; msg(c,u.name.." got the party moving.")
    elseif kind=="disarm" then local closest; for _,e in ipairs(b.units) do if e.team=="enemy" and e.hp>0 and (not closest or c.BattleRules.distance(u,e)<c.BattleRules.distance(u,closest)) then closest=e end end; if closest then c.BattleRules.applyTemporaryStat(closest,"aim",-profile.aimPenalty,profile.rounds); msg(c,closest.name.." was disarmed and weakened.") end
    elseif kind=="volley" then local closest; for _,e in ipairs(b.units) do if e.team=="enemy" and e.hp>0 and (not closest or c.BattleRules.distance(u,e)<c.BattleRules.distance(u,closest)) then closest=e end end; if closest then closest.hp=math.max(0,closest.hp-profile.damage); closest.hitTimer=.58; closest.damageNumber=profile.damage; closest.damageNumberTimer=.9; msg(c,u.name.." hit "..closest.name.." with a volley for "..profile.damage.." damage.") end end
    Battle.advance(c)
end
function Battle.resolve(c,attacker,target,weaponName)
    local b=c.battle; local C=c.Catalog; local d=c.saveData; local stats=C.weaponStats[weaponName] or C.weaponStats.scratch; local combat=C.weaponCombat[weaponName] or C.weaponCombat.scratch; local distance=c.BattleRules.distance(attacker,target); local range=c.BattleRules.weaponRange(C,weaponName)
    if distance>range then prompt(c,stats.name.." is out of range ("..range.." terrain spaces)."); return false end
    local durability=attacker.team=="ally" and weaponName~="scratch" and (d.weaponDurability[weaponName] or 100) or 100
    local condition=LootProgression.weaponCondition(durability)
    if attacker.team=="ally" and weaponName~="scratch" and condition.multiplier==0 then msg(c,attacker.name.." cannot use "..stats.name.." because it is broken. Repair it in the train workshop."); return false end
    if combat.ammo and attacker.team=="ally" then local count=d.ammo[combat.ammo] or 0; if count<=0 then msg(c,attacker.name.." has no "..c.Util.titleFromFile(combat.ammo).." ammunition."); return false end; d.ammo[combat.ammo]=count-1 end
    attacker.action=combat.kind=="ranged" and "ranged" or "melee"; attacker.actionItem=weaponName; attacker.actionTimer=attacker.team=="enemy" and .68 or .45; c.playSfx(c.weaponSfx(weaponName,combat,attacker)); if combat.kind=="ranged" then b.projectile={fromQ=attacker.q,fromR=attacker.r,toQ=target.q,toR=target.r,ammo=combat.ammo or "rocks",weapon=weaponName,kind=combat.projectile,t=0,duration=attacker.team=="enemy" and .62 or .42} end
    if attacker.team=="ally" and weaponName~="scratch" then LootProgression.wearWeapon(d,weaponName,1) end
    local prof=0
    if attacker.id=="player" then local family=C.weaponFamily(weaponName); local uses=(d.weaponProficiency[family] or 0)+1; d.weaponProficiency[family]=uses; prof=math.min(5,math.floor(uses/10)) end
    local _,cover=c.BattleRules.terrainAt(b,target.q,target.r); local roll=love.math.random(1,20); local levelAttack=attacker.id=="player" and c.PlayerProgression.combatBonuses(d.stats.level).attack or 0; local bonus=(attacker.aim or 0)+levelAttack; local defense=8+(target.armor or 0)+cover+(distance>1 and distance-1 or 0); local name=C.weaponStats[weaponName] and C.weaponStats[weaponName].name or c.Util.titleFromFile(weaponName)
    if not attacker.perfectAccuracy and (roll==1 or (roll~=20 and roll+bonus<defense)) then msg(c,attacker.name.." used "..name.." against "..target.name.." — MISS."); b.attackTimer=attacker.team=="enemy" and .90 or .45; advanceAttack(c,attacker); return true end
    local raw=love.math.random(stats.min,stats.max)+(attacker.aim or 0)+prof+(roll==20 and 3 or 0); local damage=math.max(1,math.floor(raw*condition.multiplier)-(target.armor or 0)); if target.guarding then damage=love.math.random()<.30 and 0 or math.max(1,math.floor(damage*.4)); target.guarding=false end
    target.hp=math.max(0,target.hp-damage); target.hitTimer=.58; target.damageNumber=damage; target.damageNumberTimer=.9; if target.id=="player" then d.health=target.hp end
    msg(c,attacker.name.." used "..name.." on "..target.name.." — HIT for "..damage.." damage."); b.attackTimer=attacker.team=="enemy" and .95 or .45; b.hitFlash=.18; b.lastTarget=target.id; advanceAttack(c,attacker); return true
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
