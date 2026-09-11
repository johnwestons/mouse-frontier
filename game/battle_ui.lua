local BattleRules = require("game.battle_rules")
local Catalog = require("game.catalog")
local Util = require("game.util")
local WeaponAttachment = require("game.weapon_attachment")
local Grid = require("game.battle_grid")
local Accessibility = require("game.accessibility")
local Typography = require("game.typography")

local BattleUI = {}
local function text(value,x,y,w,h,scale,minimum,align)
    return Typography.drawText(love.graphics,value,x,y,w,h,{scale=scale,minScale=minimum or scale,align=align or "left",valign="center"})
end
local function weaponButtonLabel(Catalog,Util,item)
    local name=(Catalog.weaponStats[item] and Catalog.weaponStats[item].name) or Util.titleFromFile(item)
    name=name:gsub("^Frontier%s+",""):gsub("%s+Pocket%s+"," ")
    if #name>19 then name=name:gsub("%s+Pistol$"," P."):gsub("%s+Revolver$"," REV.") end
    return name
end
local function boardToScreen(ctx,q,r)
    return Grid.boardToScreen(1,q,r)
end

function BattleUI.screenToBoardSpace(ctx,x,y)
    return Grid.screenToBoardSpace(ctx.battle,1,x,y)
end

function BattleUI.draw(ctx)
    local W,H=ctx.W,ctx.H
    local battle,scenery,colors=ctx.battle,ctx.scenery,ctx.colors
    local characterImages,npcImages,mobImages=ctx.characterImages,ctx.npcImages,ctx.mobImages
    local characterWalkImages,npcWalkImages=ctx.characterWalkImages,ctx.npcWalkImages
    local mobAttackImages,mobIdleImages,mobHitImages=ctx.mobAttackImages,ctx.mobIdleImages,ctx.mobHitImages
    local mobDeathImages,mobWalkImages,mobRangedImages=ctx.mobDeathImages,ctx.mobWalkImages,ctx.mobRangedImages
    local animationClock,characterAnimations=ctx.animationClock,ctx.characterAnimations
    local saveData,inventoryOpen,ui=ctx.saveData,ctx.inventoryOpen,ctx.ui
    local mobile=ctx.mobileEnabled
    local highContrast=Accessibility.enabled(saveData,"highContrast")
    local textScale=Accessibility.textScale(saveData)
    local drawLandscape,drawGround=ctx.drawLandscape,ctx.drawGround
    local drawAnimatedCharacter,button,screenToGame=ctx.drawAnimatedCharacter,ctx.button,ctx.screenToGame
    drawLandscape(); drawGround()
    love.graphics.setColor(highContrast and 0 or .06,highContrast and 0 or .045,highContrast and 0 or .035,highContrast and .98 or .88); love.graphics.rectangle("fill",25,12,910,668,12,12)
    if highContrast then love.graphics.setColor(1,.84,.28,1); love.graphics.setLineWidth(4); love.graphics.rectangle("line",25,12,910,668,12,12); love.graphics.setLineWidth(1) end
    -- The northern scenery reaches above its board tile. Keep the heading in
    -- the free top band and put touch hints on the feed, clear of that artwork.
    love.graphics.setColor(colors.cream); text("TACTICAL ENCOUNTER  •  ROUND "..battle.round,25,18,910,30,1.25,1,"center")
    love.graphics.setColor(colors.brass); text("OBJECTIVE  •  "..(battle.objective or "Defeat all threats"),190,51,580,24,mobile and .80 or .72,.68,"center")
    -- Inspecting a unit changes its information card, never who owns the turn.
    local active=BattleRules.activeUnit(battle)
    local inspected=BattleRules.selectedUnit(battle)
    local terrainAtlas=scenery.battleAtlases and scenery.battleAtlases[battle.biome or 1]
    if terrainAtlas then
        local reachableSpaces=active and active.team=="ally" and BattleRules.reachable(battle,active,active.move) or {}
        for depth=1,Grid.COLS+Grid.ROWS do for q=0,Grid.COLS do local r=depth-q; if BattleRules.isBoardSpace(battle,q,r) then
            local x,y=boardToScreen(ctx,q,r); local tile=battle.tiles[q][r]
            local variation=scenery.battleVariations and scenery.battleVariations[battle.biome or 1]
            local accent=scenery.battleAccents and scenery.battleAccents[battle.biome or 1]
            local variant=battle.tileVariants and battle.tileVariants[q] and battle.tileVariants[q][r] or 1
            local tileAtlas=(variant==3 and accent) or (variant==2 and variation) or terrainAtlas
            local quad=tileAtlas.quads[tile]
            if quad then love.graphics.setColor(1,1,1); love.graphics.draw(tileAtlas.image,quad,x,y,0,.30,.30,tileAtlas.cw/2,tileAtlas.ch*.42) end
            local occupant=BattleRules.unitAt(battle,q,r); local reachable=reachableSpaces[tostring(q)..":"..tostring(r)] and not occupant and not BattleRules.blocksMovement(battle,q,r)
            local targetable=active and battle.phase=="target" and occupant and occupant.team~=active.team and BattleRules.distance(active,occupant)<=BattleRules.weaponRange(Catalog,battle.chosenWeapon or "scratch") and BattleRules.lineOfSight(battle,active,occupant)
            if targetable then love.graphics.setColor(1,.12,.08,highContrast and 1 or .60); love.graphics.setLineWidth(highContrast and 6 or 3); love.graphics.circle("line",x,y,highContrast and 13 or 10); if highContrast then love.graphics.line(x-8,y,x+8,y); love.graphics.line(x,y-8,x,y+8) end
            elseif reachable and (battle.phase=="select" or battle.phase=="move") then love.graphics.setColor(1,.88,.18,highContrast and 1 or .40); love.graphics.setLineWidth(highContrast and 5 or 2); love.graphics.circle("line",x,y,highContrast and 11 or 8) end
        end end end
    end
    if scenery.battleObstacles then
        local obstacleAtlas=scenery.battleObstacles; local ordered={}
        for _,obstacle in pairs(battle.obstacles or {}) do ordered[#ordered+1]=obstacle end
        table.sort(ordered,function(a,b) return a.q+a.r<b.q+b.r end)
        for _,obstacle in ipairs(ordered) do
            local profile=Grid.profile(obstacle); local quad=profile and obstacleAtlas.quads[profile.sprite]
            if quad then local x,y=boardToScreen(ctx,obstacle.q,obstacle.r); love.graphics.setColor(1,1,1); love.graphics.draw(obstacleAtlas.image,quad,x,y+12,0,.30,.30,obstacleAtlas.cw/2,obstacleAtlas.ch*.88) end
        end
    end
    -- Draw tactical units from the back of the isometric board to the front.
    -- Dead units are deliberately first at the same depth, so a death sprite
    -- cannot cover a living character that has moved onto its space.
    local drawUnits={}
    for index,u in ipairs(battle.units) do drawUnits[#drawUnits+1]={unit=u,index=index} end
    table.sort(drawUnits,function(a,b)
        local au,bu=a.unit,b.unit
        local aDepth=(au.q or 0)+(au.r or 0); local bDepth=(bu.q or 0)+(bu.r or 0)
        if aDepth~=bDepth then return aDepth<bDepth end
        local aDead=au.hp<=0 and 0 or 1; local bDead=bu.hp<=0 and 0 or 1
        if aDead~=bDead then return aDead<bDead end
        return a.index<b.index
    end)
    for _,entry in ipairs(drawUnits) do
        local i,u=entry.index,entry.unit
        local x,y=boardToScreen(ctx,u.q,u.r); local moving=u.moveAnim~=nil
        if moving then local m=u.moveAnim; local p=math.min(1,m.t/m.duration); p=p*p*(3-2*p); local sx,sy=boardToScreen(ctx,m.fromQ,m.fromR); local tx,ty=boardToScreen(ctx,m.toQ,m.toR); x,y=sx+(tx-sx)*p,sy+(ty-sy)*p end
        if (u.hitTimer or 0)>0 and u.hitFromQ then
            local fromX,fromY=boardToScreen(ctx,u.hitFromQ,u.hitFromR); local dx,dy=x-fromX,y-fromY; local length=math.max(1,math.sqrt(dx*dx+dy*dy)); local recoil=math.sin(math.min(1,(.58-u.hitTimer)/.58)*math.pi)*14
            x=x+(dx/length)*recoil; y=y+(dy/length)*recoil-recoil*.22
        end
        local img=u.team=="enemy" and mobImages[u.file] or (characterImages[u.file] or npcImages[u.file])
        if u.hp<=0 then img=u.team=="enemy" and (mobDeathImages[u.file] or mobHitImages[u.file] or img) or img end
        if u.team=="enemy" and not moving then
            if u.hp<=0 then img=mobDeathImages[u.file] or mobHitImages[u.file] or img
            elseif (u.hitTimer or 0)>0 then img=mobHitImages[u.file] or img
            elseif (u.actionTimer or 0)>0 then img=(u.action=="ranged" and mobRangedImages[u.file]) or mobAttackImages[u.file] or img
            elseif math.floor((animationClock+i*.17)/1.25)%2==1 then img=mobIdleImages[u.file] or img end
        end
        local bob=moving and math.sin(animationClock*10+i)*3 or 0
        if moving then
            if u.team=="enemy" then img=mobWalkImages[u.file] or img
            else img=characterWalkImages[u.file] or npcWalkImages[u.file] or img end
        end
        local action=(u.hitTimer or 0)>0 and "hit" or ((u.actionTimer or 0)>0 and (u.action or "idle") or "idle")
        local facing=BattleRules.facing(battle,u)
        local actionPhase=(u.actionTimer or 0)>0 and math.max(0,.45-u.actionTimer) or animationClock+i*.13
        local attachedWeapon=false
        local animated=u.team=="ally" and drawAnimatedCharacter(u.file,u.hp<=0 and "unconscious" or (moving and "walk" or action),x,y+20,76,96,facing,moving and animationClock or actionPhase)
        if not animated and img then
            local spriteW,spriteH=u.boss and 108 or 76,u.boss and 132 or 96
            local s=math.min(spriteW/img:getWidth(),spriteH/img:getHeight())
            if battle.lastTarget==u.id and battle.hitFlash>0 then love.graphics.setColor(1,.3,.25) else love.graphics.setColor(1,1,1) end
            love.graphics.draw(img,x,y+10+bob,0,s*facing,s,img:getWidth()/2,img:getHeight())
        end
        if animated and u.team=="ally" and (action=="melee" or action=="ranged") and (u.actionTimer or 0)>0 and u.actionItem and u.actionItem~="scratch" then
            local combat=Catalog.weaponCombat[u.actionItem] or {}
            local sprite=WeaponAttachment.itemSprite(ui,u.actionItem)
            attachedWeapon=WeaponAttachment.draw(characterAnimations,u.file,u.actionItem,sprite,x,y+20,76,96,facing,actionPhase,action,combat)
        end
        if (u.actionTimer or 0)>0 and u.actionItem and u.actionItem~="scratch" and not attachedWeapon then
            local combat=Catalog.weaponCombat[u.actionItem] or {}; local progress=1-math.min(1,(u.actionTimer or 0)/(u.team=="enemy" and .68 or .45)); local reach=math.sin(progress*math.pi)
            local ox,oy=10,-38
            if combat.animation=="thrust" or combat.animation=="jab" then ox=ox+facing*reach*24
            elseif combat.animation=="smash" then oy=oy-reach*22
            elseif combat.animation=="slash" or combat.animation=="chop" or combat.animation=="swing" then ox=ox+facing*reach*14; oy=oy+reach*10 end
            ui.drawItem(u.actionItem,{x=x+ox,y=y+oy,w=38,h=38})
        end
        if (u.damageNumberTimer or 0)>0 and u.damageNumber then
            local rise=(.9-u.damageNumberTimer)*24
            love.graphics.setColor(1,.12,.08,math.min(1,u.damageNumberTimer*2)); text("-"..u.damageNumber,x-35,y-55-rise,70,26,1.15,1,"center")
        end
        if u.hp>0 then
            local hpHeight=highContrast and 12 or 8
            love.graphics.setColor(highContrast and 0 or .1,highContrast and 0 or .06,highContrast and 0 or .04,.96); love.graphics.rectangle("fill",x-31,y+14,62,hpHeight); love.graphics.setColor(u.team=="enemy" and colors.red or colors.green); love.graphics.rectangle("fill",x-31,y+14,62*(u.hp/u.maxHP),hpHeight)
            if highContrast then love.graphics.setColor(1,1,1,1); love.graphics.setLineWidth(2); love.graphics.rectangle("line",x-31,y+14,62,hpHeight); love.graphics.setLineWidth(1) end
            local status
            if u.boss then status="BOSS"
            elseif (u.sleepRounds or 0)>0 then status="SLEEP"
            elseif (u.paralyzedRounds or 0)>0 then status="PARALYZED"
            elseif (u.bleedRounds or 0)>0 then status="BLEEDING"
            elseif (u.staggeredRounds or 0)>0 then status="STAGGERED"
            elseif (u.moveBonus or 0)<0 then status="SNARED"
            elseif u.guarding then status="GUARD"
            elseif (u.regenRounds or 0)>0 then status="REGEN" end
            if status then love.graphics.setColor(colors.brass); local statusScale=(mobile and .66 or .55)*textScale; text(status,x-50,y+29,100,19,statusScale,.55,"center") end
        end
    end
    if battle.projectile and scenery.projectiles then
        local p=battle.projectile; local sx,sy=boardToScreen(ctx,p.fromQ,p.fromR); local tx,ty=boardToScreen(ctx,p.toQ,p.toR); local progress=math.min(1,p.t/p.duration); local px,py=sx+(tx-sx)*progress,sy+(ty-sy)*progress-35
        if p.kind=="boomerang" and ui.propImages["scrap-boomerang"] then
            local image=ui.propImages["scrap-boomerang"]; local scale=math.min(38/image:getWidth(),38/image:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(image,px,py,progress*math.pi*6,scale,scale,image:getWidth()/2,image:getHeight()/2)
        else
            local index=p.ammo=="rocks" and 1 or (p.ammo=="ball-bearings" and 2 or (p.ammo=="arrows" and 3 or ((p.ammo=="45-cal" or p.ammo=="556") and 5 or 4)))
            local atlas=scenery.projectiles; local scale=math.min(34/atlas.w,22/atlas.h); love.graphics.setColor(1,1,1); love.graphics.draw(atlas.image,atlas.quads[index],px,py,math.atan2(ty-sy,tx-sx),scale,scale,atlas.w/2,atlas.h/2)
        end
    end
    -- Paint the controls backing before the card/feed so mobile actions never
    -- cover the current unit's health or the most recent combat result.
    if not battle.finished and active and active.team=="ally" then
        love.graphics.setColor(.055,.038,.028,.97); love.graphics.rectangle("fill",8,mobile and 488 or 575,944,mobile and 220 or 105,9,9)
    end
    local feedX,feedY,feedW,feedH=mobile and 20 or 185,mobile and 414 or 476,mobile and 920 or 590,mobile and 82 or 94
    love.graphics.setColor(highContrast and 0 or .08,highContrast and 0 or .055,highContrast and 0 or .04,highContrast and .98 or .92); love.graphics.rectangle("fill",feedX,feedY,feedW,feedH,8,8)
    love.graphics.setColor(colors.brass); text("BATTLE FEED",feedX+20,feedY+7,feedW-40,20,.82,.72)
    if Accessibility.enabled(saveData,"controlHints") then
        local hint=mobile and "TAP UNIT / TILE  •  PINCH TO ZOOM" or "CLICK: SELECT  •  RIGHT CLICK: INSPECT  •  WHEEL: ZOOM"
        love.graphics.setColor(colors.cream); text(hint,feedX+165,feedY+7,feedW-185,20,(mobile and .72 or .60)*math.min(textScale,1.18),.58,"right")
    end
    local log=battle.log or {battle.message}; local visible=mobile and 1 or 2
    local offset=math.max(0,math.min(battle.logScroll or 0,math.max(0,#log-visible))); battle.logScroll=offset
    local newest=#log-(mobile and 0 or offset); local first=math.max(1,newest-visible+1); local row=0
    local feedScale=(mobile and .90 or .70)*math.min(textScale,1.22)
    love.graphics.setColor(colors.cream)
    for i=first,newest do
        text(log[i],feedX+20,feedY+28+row*30,mobile and feedW-40 or 520,mobile and 48 or 30,feedScale,mobile and .78 or .64)
        row=row+1
    end
    if mobile then ui.battleLogUp=nil; ui.battleLogDown=nil
    else ui.battleLogUp=button("^",735,500,28,27,offset<#log-1); ui.battleLogDown=button("v",735,533,28,27,offset>0) end
    ui.battleWeapons={}; ui.battlePotionButtons={}; ui.battleHeal=nil; ui.battleGuard=nil; ui.battleAbility=nil; ui.battleEnd=nil; ui.battleRetreat=nil; ui.battleMove=nil; ui.battleInventory=nil
    if terrainAtlas then love.graphics.setColor(colors.cream); text(terrainAtlas.name,790,105,135,35,.75,.65,"right") end
    if inspected then
        -- Character card occupies the lower-left corner between the battle
        -- feed and the attack controls, leaving the tactical map unobstructed.
        local cardX,cardY=mobile and 660 or 8,mobile and 498 or 488
        love.graphics.setColor(.08,.055,.04,.94); love.graphics.rectangle("fill",cardX,cardY,mobile and 282 or 168,mobile and 62 or 82,8,8)
        love.graphics.setColor(colors.brass); text(inspected==active and "ACTIVE" or "INSPECT",cardX+6,cardY+4,50,16,.62,.58)
        local portrait=inspected.team=="enemy" and mobImages[inspected.file] or (characterImages[inspected.file] or npcImages[inspected.file])
        if portrait then local portraitScale=math.min(42/portrait:getWidth(),(mobile and 34 or 48)/portrait:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(portrait,cardX+34,cardY+(mobile and 51 or 64),0,portraitScale,portraitScale,portrait:getWidth()/2,portrait:getHeight()) end
        love.graphics.setColor(colors.cream); text(inspected.name,cardX+60,cardY+(mobile and 3 or 6),mobile and 212 or 100,mobile and 18 or 30,mobile and .85 or .62,mobile and .72 or .54)
        text("HP "..inspected.hp.."/"..inspected.maxHP,cardX+60,cardY+(mobile and 23 or 36),mobile and 212 or 100,18,mobile and .84 or .65,.60)
        text("MOVE "..inspected.move.."  ARM "..inspected.armor,cardX+60,cardY+(mobile and 43 or 56),mobile and 212 or 100,16,mobile and .70 or .55,.52)
    end
    if battle.finished then
        local expedition=battle.encounter and battle.encounter.source=="expedition"
        local label=battle.finished=="win" and (expedition and "RETURN TO AREA" or "CONTINUE TO STOP") or "RETURN TO TRAIN"
        ui.battleContinue=button(label,mobile and 300 or 330,mobile and 585 or 605,mobile and 360 or 300,mobile and 70 or 45,true)
    elseif active and active.team=="ally" then
        if not mobile then love.graphics.setColor(colors.brass); love.graphics.print("ATTACK",20,578,0,.54,.54); love.graphics.print("ACTIONS",548,578,0,.54,.54) end
        local options={"scratch"}; if active.id=="player" then for i=1,2 do if saveData.equipment[i] then options[#options+1]=saveData.equipment[i] end end elseif active.weapon then options[#options+1]=active.weapon end; battle.options=options
        for i,w in ipairs(options) do
            local bx=20+(i-1)*(mobile and 210 or 174)
            ui.battleWeapons[i]=button((i).."  "..weaponButtonLabel(Catalog,Util,w),bx,mobile and 506 or 592,mobile and 200 or 166,mobile and 54 or 34,true,mobile and .62 or .56)
            local mx,my=screenToGame(ctx.pointerPosition())
            if not mobile and Util.pointIn(mx,my,ui.battleWeapons[i]) then
                local stats=Catalog.weaponStats[w] or Catalog.weaponStats.scratch
                local combat=Catalog.weaponCombat[w] or Catalog.weaponCombat.scratch
                local durability=(w=="scratch") and 100 or (saveData.weaponDurability[w] or 100)
                local details=string.format("%s  DMG %d-%d  %s  REACH %d",stats.name,stats.min,stats.max,combat.kind=="melee" and Catalog.weaponRole(w) or string.upper(combat.kind or "melee"),Catalog.weaponReach(w))
                if combat.ammo then details=details.."  "..Util.titleFromFile(combat.ammo).." "..(saveData.ammo[combat.ammo] or 0) end
                details=details.."  DUR "..durability.."%"..(durability<=0 and " BROKEN" or "")
                love.graphics.setColor(colors.panel[1],colors.panel[2],colors.panel[3],.96); love.graphics.rectangle("fill",190,535,580,38,5,5)
                love.graphics.setColor(colors.cream); text(details,200,538,560,32,.67,.60,"center")
            end
        end
        ui.battleMove=button(battle.moveUsed and "MOVE USED" or "MOVE",mobile and 20 or 548,mobile and 570 or 592,mobile and 200 or 94,mobile and 54 or 34,not battle.moveUsed,.66)
        ui.battleHeal=button("HEAL",mobile and 240 or 648,mobile and 570 or 592,mobile and 200 or 94,mobile and 54 or 34,true,.66)
        ui.battleGuard=button("GUARD",mobile and 460 or 748,mobile and 570 or 592,mobile and 200 or 94,mobile and 54 or 34,true,.66)
        local abilityBase=Catalog.characterAbility(active.file or "")
        local abilityLevel=active.id=="player" and saveData.stats.level or math.max(1,math.min(12,math.ceil((saveData.location or 1)/5)))
        local abilityProfile=ctx.playerProgression.abilityProfile(abilityBase.kind,abilityLevel)
        ui.battleAbility=button("ABILITY R"..abilityProfile.rank,mobile and 680 or 848,mobile and 570 or 592,mobile and 200 or 94,mobile and 54 or 34,not battle.abilitiesUsed[active.id],.60)
        ui.battleInventory=button("BACKPACK",20,mobile and 634 or 638,mobile and 200 or 105,mobile and 54 or 34,true,.68)
        if not mobile then love.graphics.setColor(colors.brass); love.graphics.print("QUICK ITEMS",135,628,0,.44,.44) end
        local potionIndex=0
        for i=1,(saveData.inventoryCapacity or 6) do
            local item=saveData.inventory[i]; local effect=item and Catalog.itemEffects[item]
            if not mobile and effect and effect.potion and potionIndex<5 then
                potionIndex=potionIndex+1; local px=135+(potionIndex-1)*100
                ui.battlePotionButtons[potionIndex]={button(string.upper(effect.shortName or effect.potion),px,642,92,30,true,.44),name=item}
            end
        end
        ui.battleEnd=button("END TURN",mobile and 460 or 665,mobile and 634 or 638,mobile and 250 or 140,mobile and 54 or 34,true,.72)
        ui.battleRetreat=button("RETREAT",mobile and 730 or 815,mobile and 634 or 638,mobile and 200 or 127,mobile and 54 or 34,true,.72)
        if mobile and Accessibility.enabled(saveData,"controlHints") then
            local hintScale=.76*math.min(textScale,1.15)
            love.graphics.setColor(0,0,0,.92); love.graphics.rectangle("fill",240,634,200,54,5,5)
            love.graphics.setColor(colors.cream); text(abilityProfile.description,246,637,188,48,hintScale,.65,"center")
        end
        local mx,my=screenToGame(ctx.pointerPosition())
        if not mobile and Util.pointIn(mx,my,ui.battleAbility) then
            love.graphics.setColor(colors.panel[1],colors.panel[2],colors.panel[3],.96); love.graphics.rectangle("fill",545,518,395,55,5,5)
            love.graphics.setColor(colors.cream); text(abilityBase.name.." RANK "..abilityProfile.rank.."  •  "..abilityProfile.description,557,522,371,46,.72,.60,"center")
        end
    end
    if battle.intro then
        local p=math.min(1,battle.intro/battle.introDuration)
        local fadeIn=math.min(1,p/.35); local fadeOut=math.min(1,math.max(0,(1-p)/.45))
        local alpha=math.max(0,math.min(1,math.max(fadeIn,fadeOut)))
        love.graphics.setColor(0.025,0.018,0.012,alpha*.78); love.graphics.rectangle("fill",0,0,W,H)
        love.graphics.setColor(colors.cream,alpha); text("ENCOUNTER",0,298,W,50,2.3,1.8,"center")
        text("A threat blocks the trail",0,350,W,30,1.05,1,"center")
    end
    if inventoryOpen then
        love.graphics.setColor(0,0,0,.58); love.graphics.rectangle("fill",0,0,W,H)
        ui.drawInventory()
        ui.battleInventoryClose=button(mobile and "CLOSE BACKPACK" or "CLOSE [I]",mobile and 300 or 425,35,mobile and 210 or 105,mobile and 66 or 38,true)
        love.graphics.setColor(colors.cream)
        text("BATTLE BACKPACK\nUse medicine or potions, or drag weapons into the equipped slots.",35,mobile and 112 or 88,480,96,mobile and 1 or .85,.78,"center")
    else ui.battleInventoryClose=nil end
    love.graphics.setLineWidth(1)
end

function BattleUI.handleMouse(ctx,x,y,rightClick)
    local battle,ui=ctx.battle,ctx.ui
    if not battle then return "missing" end
    if battle.intro then return "handled" end
    if ctx.inventoryOpen then
        if Util.pointIn(x,y,ui.battleInventoryClose) then ctx.setInventoryOpen(false); ctx.resetInventoryDrag()
        else ctx.handleInventoryClick(x,y) end
        return "handled"
    end
    if Util.pointIn(x,y,ui.battleLogUp) then ui.playSfx("menu"); battle.logScroll=math.min(math.max(0,#(battle.log or {})-1),(battle.logScroll or 0)+1); return "handled" end
    if Util.pointIn(x,y,ui.battleLogDown) then ui.playSfx("menu"); battle.logScroll=math.max(0,(battle.logScroll or 0)-1); return "handled" end
    if battle.finished and Util.pointIn(x,y,ui.battleContinue) then
        ui.playSfx("menu")
        return battle.finished=="win" and "continue_win" or "continue_loss"
    end
    if battle.finished then return "handled" end
    if rightClick then
        local q,r=BattleUI.screenToBoardSpace(ctx,x,y); local clicked=q and BattleRules.unitAt(battle,q,r)
        if clicked then battle.selected=clicked.id; ui.playSfx("menu") end
        return "handled"
    end
    local active=BattleRules.activeUnit(battle)
    -- A click can arrive after a turn changes and before the next draw clears
    -- the old button rectangles. Do not let stale controls skip an enemy turn.
    if not active or active.team~="ally" or active.hp<=0 then return "handled" end
    if Util.pointIn(x,y,ui.battleInventory) then ctx.setInventoryOpen(true); ctx.resetInventoryDrag(); ui.playSfx("menu"); return "handled" end
    for i,r in ipairs(ui.battleWeapons or {}) do if Util.pointIn(x,y,r) then ui.playSfx("menu"); ctx.battleAttack(battle.options[i]); return "handled" end end
    if Util.pointIn(x,y,ui.battleMove) and not battle.moveUsed then ui.playSfx("menu"); battle.phase="move"; ctx.setBattlePrompt("Choose a highlighted terrain piece to move."); return "handled" end
    if Util.pointIn(x,y,ui.battleHeal) then ui.playSfx("menu"); ctx.battleHeal(); return "handled" end
    if Util.pointIn(x,y,ui.battleGuard) then ui.playSfx("menu"); ctx.battleGuard(); return "handled" end
    if Util.pointIn(x,y,ui.battleAbility) then
        ui.playSfx("menu")
        local unit=BattleRules.activeUnit(battle); local abilityProfile=Catalog.characterAbility(unit and unit.file or "")
        ctx.useBattleAbility(abilityProfile.kind); return "handled"
    end
    for _,entry in ipairs(ui.battlePotionButtons or {}) do
        if Util.pointIn(x,y,entry[1]) then ui.playSfx("menu"); ctx.useBattlePotion(entry[2]); return "handled" end
    end
    if Util.pointIn(x,y,ui.battleEnd) then ui.playSfx("menu"); ctx.advanceBattleTurn(); return "handled" end
    if Util.pointIn(x,y,ui.battleRetreat) then ui.playSfx("menu"); ctx.saveData.battlePotionLootChance=nil; return "retreat" end
    local q,r=BattleUI.screenToBoardSpace(ctx,x,y)
    if q then
        local clicked=BattleRules.unitAt(battle,q,r)
        if clicked and battle.phase=="target" and clicked.team=="enemy" then
            ctx.resolveBattleAttack(active,clicked,battle.chosenWeapon or "scratch")
            return "handled"
        elseif clicked then
            if clicked.team=="ally" and battle.phase~="target" then battle.selected=clicked.id end
            return "handled"
        end
    end
    if q and active and active.team=="ally" then
        local target=BattleRules.unitAt(battle,q,r)
        if battle.phase=="target" and target and target.team=="enemy" then ctx.resolveBattleAttack(active,target,battle.chosenWeapon or "scratch")
        elseif not target then ctx.battleMoveTo(q,r) end
    end
    return "handled"
end

return BattleUI
