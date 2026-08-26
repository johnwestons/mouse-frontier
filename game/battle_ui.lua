local BattleRules = require("game.battle_rules")
local Catalog = require("game.catalog")
local Util = require("game.util")
local WeaponAttachment = require("game.weapon_attachment")
local Grid = require("game.battle_grid")

local BattleUI = {}
local function boardToScreen(ctx,q,r)
    return Grid.boardToScreen(1,q,r)
end

function BattleUI.screenToBoardSpace(ctx,x,y)
    return Grid.screenToBoardSpace(ctx.battle,ctx.battleZoom,x,y)
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
    local drawLandscape,drawGround=ctx.drawLandscape,ctx.drawGround
    local drawAnimatedCharacter,button,screenToGame=ctx.drawAnimatedCharacter,ctx.button,ctx.screenToGame
    drawLandscape(); drawGround()
    love.graphics.setColor(0.06,0.045,0.035,.88); love.graphics.rectangle("fill",25,55,910,625,12,12)
    love.graphics.setColor(colors.cream); love.graphics.printf("TACTICAL ENCOUNTER  •  ROUND "..battle.round,25,70,910,"center",0,1.25,1.25)
    love.graphics.setColor(colors.brass); love.graphics.printf("OBJECTIVE  •  "..(battle.objective or "Defeat all threats"),260,98,440,"center",0,.58,.58)
    local active=BattleRules.selectedUnit(battle)
    local terrainAtlas=scenery.battleAtlases and scenery.battleAtlases[battle.biome or 1]
    local zoom=ctx.battleZoom or 1
    love.graphics.push(); love.graphics.translate(Grid.ORIGIN_X,Grid.ORIGIN_Y); love.graphics.scale(zoom,zoom); love.graphics.translate(-Grid.ORIGIN_X,-Grid.ORIGIN_Y)
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
            if targetable then love.graphics.setColor(1,.12,.08,.60); love.graphics.setLineWidth(3); love.graphics.circle("line",x,y,10)
            elseif reachable and (battle.phase=="select" or battle.phase=="move") then love.graphics.setColor(1,.80,.18,.40); love.graphics.setLineWidth(2); love.graphics.circle("line",x,y,8) end
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
        if not animated and img then local s=math.min(76/img:getWidth(),96/img:getHeight()); if battle.lastTarget==u.id and battle.hitFlash>0 then love.graphics.setColor(1,.3,.25) else love.graphics.setColor(1,1,1) end; love.graphics.draw(img,x,y+10+bob,0,s*facing,s,img:getWidth()/2,img:getHeight()) end
        if animated and u.team=="ally" and action=="ranged" and (u.actionTimer or 0)>0 and WeaponAttachment.isFirearm(Catalog,u.actionItem) then
            attachedWeapon=WeaponAttachment.draw(characterAnimations,u.file,u.actionItem,ui.propImages[u.actionItem],x,y+20,76,96,facing,actionPhase)
        end
        if (u.actionTimer or 0)>0 and u.actionItem and u.actionItem~="scratch" and not attachedWeapon then ui.drawItem(u.actionItem,{x=x+10,y=y-38,w=38,h=38}) end
        if (u.damageNumberTimer or 0)>0 and u.damageNumber then
            local rise=(.9-u.damageNumberTimer)*24
            love.graphics.setColor(1,.12,.08,math.min(1,u.damageNumberTimer*2)); love.graphics.printf("-"..u.damageNumber,x-35,y-55-rise,70,"center",0,1.15,1.15)
        end
        if u.hp>0 then
            love.graphics.setColor(.1,.06,.04,.9); love.graphics.rectangle("fill",x-31,y+14,62,8); love.graphics.setColor(u.team=="enemy" and colors.red or colors.green); love.graphics.rectangle("fill",x-31,y+14,62*(u.hp/u.maxHP),8)
            local status=u.boss and "BOSS" or ((u.sleepRounds or 0)>0 and "SLEEP" or ((u.paralyzedRounds or 0)>0 and "PARALYZED" or ((u.moveBonus or 0)<0 and "SNARED" or (u.guarding and "GUARD" or ((u.regenRounds or 0)>0 and "REGEN" or nil)))))
            if status then love.graphics.setColor(colors.brass); love.graphics.printf(status,x-45,y+25,90,"center",0,.43,.43) end
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
    love.graphics.pop()
    love.graphics.setColor(.08,.055,.04,.92); love.graphics.rectangle("fill",185,488,590,82,8,8)
    love.graphics.setColor(colors.brass); love.graphics.print("BATTLE FEED",205,497,0,.72,.72)
    local log=battle.log or {battle.message}; local offset=math.max(0,math.min(battle.logScroll or 0,math.max(0,#log-3))); battle.logScroll=offset
    local newest=#log-offset; local first=math.max(1,newest-2); local row=0
    love.graphics.setColor(colors.cream); for i=first,newest do love.graphics.printf(log[i],210,516+row*16,520,"left",0,.67,.67); row=row+1 end
    if mobile then ui.battleLogUp=nil; ui.battleLogDown=nil
    else ui.battleLogUp=button("^",735,500,28,27,offset<#log-1); ui.battleLogDown=button("v",735,533,28,27,offset>0) end
    ui.battleWeapons={}; ui.battlePotionButtons={}; ui.battleHeal=nil; ui.battleGuard=nil; ui.battleAbility=nil; ui.battleEnd=nil; ui.battleRetreat=nil; ui.battleMove=nil; ui.battleInventory=nil
    if terrainAtlas then love.graphics.setColor(colors.cream); love.graphics.print(terrainAtlas.name,790,112,0,.7,.7) end
    if active then
        -- Character card occupies the lower-left corner between the battle
        -- feed and the attack controls, leaving the tactical map unobstructed.
        love.graphics.setColor(.08,.055,.04,.94); love.graphics.rectangle("fill",8,488,168,82,8,8)
        love.graphics.setColor(colors.brass); love.graphics.printf("ACTIVE",14,495,52,"left",0,.62,.62)
        local portrait=active.team=="enemy" and mobImages[active.file] or (characterImages[active.file] or npcImages[active.file])
        if portrait then local portraitScale=math.min(42/portrait:getWidth(),48/portrait:getHeight()); love.graphics.setColor(1,1,1); love.graphics.draw(portrait,42,552,0,portraitScale,portraitScale,portrait:getWidth()/2,portrait:getHeight()) end
        love.graphics.setColor(colors.cream); love.graphics.printf(active.name,68,503,100,"left",0,.54,.54)
        love.graphics.print("HP "..active.hp.."/"..active.maxHP,68,523,0,.56,.56)
        love.graphics.print("MOVE "..active.move.."  ARM "..active.armor,68,541,0,.52,.52)
    end
    if battle.finished then ui.battleContinue=button(battle.finished=="win" and "CONTINUE TO STOP" or "RETURN TO TRAIN",mobile and 300 or 330,mobile and 585 or 605,mobile and 360 or 300,mobile and 70 or 45,true)
    elseif active and active.team=="ally" then
        love.graphics.setColor(.055,.038,.028,.97); love.graphics.rectangle("fill",8,mobile and 488 or 575,944,mobile and 220 or 105,9,9)
        if not mobile then love.graphics.setColor(colors.brass); love.graphics.print("ATTACK",20,578,0,.54,.54); love.graphics.print("ACTIONS",548,578,0,.54,.54) end
        local options={"scratch"}; if active.id=="player" then for i=1,2 do if saveData.equipment[i] then options[#options+1]=saveData.equipment[i] end end elseif active.weapon then options[#options+1]=active.weapon end; battle.options=options
        for i,w in ipairs(options) do
            local bx=20+(i-1)*(mobile and 210 or 174)
            ui.battleWeapons[i]=button((i).."  "..(Catalog.weaponStats[w] and Catalog.weaponStats[w].name or Util.titleFromFile(w)),bx,mobile and 506 or 592,mobile and 200 or 166,mobile and 54 or 34,true,.66)
            local mx,my=screenToGame(ctx.pointerPosition())
            if Util.pointIn(mx,my,ui.battleWeapons[i]) then
                local stats=Catalog.weaponStats[w] or Catalog.weaponStats.scratch
                local combat=Catalog.weaponCombat[w] or Catalog.weaponCombat.scratch
                local durability=(w=="scratch") and 100 or (saveData.weaponDurability[w] or 100)
                local details=string.format("%s  DMG %d-%d  %s  RANGE %d",stats.name,stats.min,stats.max,string.upper(combat.kind or "melee"),combat.range or 0)
                if combat.ammo then details=details.."  "..Util.titleFromFile(combat.ammo).." "..(saveData.ammo[combat.ammo] or 0) end
                details=details.."  DUR "..durability.."%"..(durability<=0 and " BROKEN" or "")
                love.graphics.setColor(colors.panel[1],colors.panel[2],colors.panel[3],.96); love.graphics.rectangle("fill",190,535,580,38,5,5)
                love.graphics.setColor(colors.cream); love.graphics.printf(details,200,546,560,"center",0,.58,.58)
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
        if not mobile then love.graphics.setColor(colors.brass); love.graphics.print("QUICK ITEMS",138,629,0,.48,.48) end
        local potionIndex=0
        for i=1,(saveData.inventoryCapacity or 6) do
            local item=saveData.inventory[i]; local effect=item and Catalog.itemEffects[item]
            if not mobile and effect and effect.potion and potionIndex<5 then
                potionIndex=potionIndex+1; local px=135+(potionIndex-1)*80
                ui.battlePotionButtons[potionIndex]={button(string.upper(effect.shortName or effect.potion),px,638,74,34,true,.52),name=item}
            end
        end
        ui.battleEnd=button("END TURN",mobile and 460 or 665,mobile and 634 or 638,mobile and 250 or 140,mobile and 54 or 34,true,.72)
        ui.battleRetreat=button("RETREAT",mobile and 730 or 815,mobile and 634 or 638,mobile and 200 or 127,mobile and 54 or 34,true,.72)
        local mx,my=screenToGame(ctx.pointerPosition())
        if Util.pointIn(mx,my,ui.battleAbility) then
            love.graphics.setColor(colors.panel[1],colors.panel[2],colors.panel[3],.96); love.graphics.rectangle("fill",545,518,395,55,5,5)
            love.graphics.setColor(colors.cream); love.graphics.printf(abilityBase.name.." RANK "..abilityProfile.rank.."  •  "..abilityProfile.description,557,535,371,"center",0,.60,.60)
        end
        love.graphics.setColor(colors.cream); love.graphics.print(active.name.."  HP "..active.hp.."/"..active.maxHP.."  MOVE "..active.move.."  ARMOR "..active.armor,65,115)
    end
    if battle.intro then
        local p=math.min(1,battle.intro/battle.introDuration)
        local fadeIn=math.min(1,p/.35); local fadeOut=math.min(1,math.max(0,(1-p)/.45))
        local alpha=math.max(0,math.min(1,math.max(fadeIn,fadeOut)))
        love.graphics.setColor(0.025,0.018,0.012,alpha*.78); love.graphics.rectangle("fill",0,0,W,H)
        love.graphics.setColor(colors.cream,alpha); love.graphics.printf("ENCOUNTER",0,300,W,"center",0,2.3,2.3)
        love.graphics.printf("A threat blocks the trail",0,350,W,"center",0,1.05,1.05)
    end
    if inventoryOpen then
        love.graphics.setColor(0,0,0,.58); love.graphics.rectangle("fill",0,0,W,H)
        ui.drawInventory()
        ui.battleInventoryClose=button(mobile and "CLOSE BACKPACK" or "CLOSE [I]",mobile and 375 or 425,35,mobile and 210 or 105,mobile and 66 or 38,true)
        love.graphics.setColor(colors.cream)
        love.graphics.printf("BATTLE BACKPACK\nUse medicine or potions, or drag weapons into the equipped slots.",35,88,480,"center",0,.78,.78)
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
    if Util.pointIn(x,y,ui.battleInventory) then ctx.setInventoryOpen(true); ctx.resetInventoryDrag(); ui.playSfx("menu"); return "handled" end
    if rightClick then
        local q,r=BattleUI.screenToBoardSpace(ctx,x,y); local clicked=q and BattleRules.unitAt(battle,q,r)
        if clicked then battle.selected=clicked.id; ui.playSfx("menu") end
        return "handled"
    end
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
    local q,r=BattleUI.screenToBoardSpace(ctx,x,y); local active=BattleRules.activeUnit(battle)
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
