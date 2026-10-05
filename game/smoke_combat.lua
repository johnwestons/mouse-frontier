local Grid=require("game.battle_grid")
local Rules=require("game.battle_rules")
local Viewport=require("game.viewport")
local WorldView=require("game.world_view")
local UIStyle=require("game.ui_layout")

local function required(context,name,kind)
    local value=context[name]
    assert(type(value)==kind,"combat smoke requires "..name.." ("..kind..")")
    return value
end

local function steps(context)
    local game=required(context,"runtime","table")
    local ui=required(context,"ui","table")
    local catalog=required(context,"catalog","table")
    local character=required(context,"character","string")
    local newSave=required(context,"newSave","function")
    local enterGame=required(context,"enterGame","function")
    local beginEncounter=required(context,"beginEncounter","function")
    local update=required(context,"update","function")
    local draw=required(context,"draw","function")
    local presentation=required(context,"presentationRuntime","table")
    local mobileEnabled=required(context,"mobileEnabled","function")
    local getMobileControls=context.getMobileControls
    local touchId=0

    local function tap(x,y)
        local ox,oy,sx,sy=Viewport.transform(960,720)
        x,y=ox+x*sx,oy+y*sy
        if mobileEnabled() then
            touchId=touchId+1
            local id="smoke-combat-"..touchId
            love.touchpressed(id,x,y)
            love.touchreleased(id,x,y)
        else
            love.mousepressed(x,y,1)
            love.mousereleased(x,y,1)
        end
    end
    local function control(rect)
        assert(rect,"combat control was not drawn")
        tap(rect.x+rect.w/2,rect.y+rect.h/2)
    end
    local function board(q,r)
        local x,y=Grid.boardToScreen(1,q,r)
        x,y=WorldView.toScreen(x,y)
        local point=UIStyle.transformRectFor("battle",{x=0,y=0,w=960,h=720},{x=x,y=y,w=0,h=0})
        tap(point.x,point.y)
    end
    local function waitUntil(predicate,message)
        for _=1,120 do
            if predicate() then return end
            update(.05)
        end
        assert(predicate(),message)
    end
    local function shoot(enemy)
        draw()
        assert(game.battle.options[3]=="trail-slingshot","equipped ranged weapon missing from attack controls")
        control(ui.battleWeapons[3])
        assert(game.battle.phase=="target","weapon button did not enter targeting")
        board(enemy.q,enemy.r)
    end

    local function fixture(seed,options,run)
        local previous={save=game.saveData,slot=game.selectedSlot,player=game.player,
            state=game.state,scene=game.scene,options=ui.optionsOpen,escape=ui.escMenuOpen,
            radio=ui.radioOpen,mobileMenu=ui.mobileMenuOpen}
        local randomState=love.math.getRandomState()
        local ok,result=xpcall(function()
            game.selectedSlot=nil
            ui.optionsOpen=false;ui.escMenuOpen=false;ui.radioOpen=false;ui.mobileMenuOpen=false
            love.math.setRandomSeed(seed)
            local data=newSave(character)
            data.location=2;data.scene="train";data.passengers={}
            enterGame(data)
            data=game.saveData
            data.maxHealth=40;data.health=options.health or 40
            data.equipment={"frontier-short-sword","trail-slingshot"}
            data.ammo.rocks=4;data.weaponDurability["trail-slingshot"]=100
            local encounter={rolled=true,hasMob=true,resolved=false,tier="easy",
                maxHP=options.enemyHP or 100,mobFiles={assert(catalog.mobTiers.easy[1])}}
            data.encounters["2"]=encounter
            beginEncounter(encounter)
            presentation.resetCamera(true)
            local battle=assert(game.battle)
            local player,enemy=battle.units[1],battle.units[2]
            assert(#battle.units==2,"combat fixture should contain exactly one player and enemy")
            -- Fixture geometry and perfect accuracy isolate action/cost rules
            -- from terrain and hit RNG. All damage and outcomes use real inputs.
            battle.obstacles={}
            for _,column in pairs(battle.tiles) do for row in pairs(column) do column[row]=1 end end
            enemy.q,enemy.r=options.enemyQ or 2,3
            enemy.armor=0;enemy.aim=2;enemy.weapon="mob-claw";enemy.attackStyle="melee"
            player.perfectAccuracy=true;enemy.perfectAccuracy=true
            draw()
            local intro=battle.intro~=nil
            control(ui.battleMove)
            assert(intro and battle.phase=="select" and not battle.moveUsed,"battle intro accepted an action")
            waitUntil(function() return battle.intro==nil end,"battle intro never completed")
            draw()
            local report=run(data,battle,player,enemy,encounter)
            report.fixture="seeded geometry and perfect accuracy; real callbacks"
            report.ok=true
            return report
        end,debug.traceback)
        game.selectedSlot=nil
        local restored,restoreError=xpcall(function()
            local controls=type(getMobileControls)=="function" and getMobileControls() or nil
            if controls then controls:cancelAll() end
            enterGame(previous.save)
            presentation.resetCamera(true)
        end,debug.traceback)
        game.saveData=previous.save;game.player=previous.player;game.scene=previous.scene;game.state=previous.state
        game.selectedSlot=previous.slot
        ui.optionsOpen=previous.options;ui.escMenuOpen=previous.escape
        ui.radioOpen=previous.radio;ui.mobileMenuOpen=previous.mobileMenu
        love.math.setRandomState(randomState)
        if not ok then error(result) end
        if not restored then error("combat fixture cleanup: "..tostring(restoreError)) end
        return result
    end
    local function scenario(name,seed,options,run)
        return {name=name,action=function() return fixture(seed,options,run) end,
            check=function(_,_,_,result) return type(result)=="table" and result.ok==true end}
    end

    return {
        scenario("combat_movement_and_blocked_spaces",401,{enemyQ=3},function(_,battle,player)
            battle.obstacles["1:2"]={kind="dead-tree",q=1,r=2}
            control(ui.battleMove);board(1,2)
            assert(player.q==1 and player.r==3 and not battle.moveUsed,"blocked movement changed player position")
            board(2,3)
            assert(player.q==2 and player.r==3 and battle.moveUsed and battle.phase=="action","legal movement did not consume the move action")
            board(2,2)
            assert(player.q==2 and player.r==3,"player moved twice in one turn")
            waitUntil(function() return player.moveAnim==nil end,"movement animation never settled")
            return {blocked=true,moved=true,repeatBlocked=true,animationSettled=true}
        end),
        scenario("combat_ranged_costs_and_enemy_turn",402,{},function(data,battle,player,enemy)
            local beforeHP,enemyHP=player.hp,enemy.hp
            local family=catalog.weaponFamily("trail-slingshot")
            local proficiency=data.weaponProficiency[family] or 0
            local staleEnd=ui.battleEnd
            shoot(enemy)
            assert(enemy.hp<enemyHP and enemy.hp>0,"actual ranged attack did not damage the surviving target")
            assert(data.ammo.rocks==3 and data.weaponDurability["trail-slingshot"]==99,"attack did not charge exactly one ammo and durability")
            assert(data.weaponProficiency[family]==proficiency+1,"attack did not advance proficiency")
            assert(battle.projectile and Rules.activeUnit(battle)==enemy,"attack did not create a projectile and advance to enemy turn")
            control(staleEnd)
            assert(Rules.activeUnit(battle)==enemy,"stale player controls skipped the enemy turn")
            waitUntil(function() return Rules.activeUnit(battle)==player end,"enemy never completed its turn")
            assert(player.hp<beforeHP and player.hp>0 and data.health==player.hp,"enemy attack did not damage and synchronize player health")
            assert(battle.round==2 and data.ammo.rocks==3 and data.weaponDurability["trail-slingshot"]==99,"turn cycle duplicated player attack costs")
            return {damage=enemyHP-enemy.hp,enemyDamage=beforeHP-player.hp,ammoUsed=1,wear=1,round=battle.round}
        end),
        scenario("combat_invalid_attacks_are_free",403,{},function(data,battle,player,enemy)
            local hp=enemy.hp
            local function unchanged(reason)
                assert(enemy.hp==hp and Rules.activeUnit(battle)==player and not battle.projectile,reason)
            end
            data.ammo.rocks=0;shoot(enemy);unchanged("empty ammo still performed an attack")
            assert(data.ammo.rocks==0 and data.weaponDurability["trail-slingshot"]==100,"empty ammo charged wear")
            data.ammo.rocks=4;data.weaponDurability["trail-slingshot"]=0
            shoot(enemy);unchanged("broken weapon still performed an attack")
            assert(data.ammo.rocks==4 and data.weaponDurability["trail-slingshot"]==0,"broken weapon charged ammo")
            data.weaponDurability["trail-slingshot"]=100;enemy.q=7
            shoot(enemy);unchanged("out of range attack damaged target")
            enemy.q=4;battle.obstacles["3:3"]={kind="dead-tree",q=3,r=3}
            shoot(enemy);unchanged("blocked line of sight attack damaged target")
            assert(data.ammo.rocks==4 and data.weaponDurability["trail-slingshot"]==100,"rejected attack charged ammo or wear")
            return {emptyAmmo=true,broken=true,outOfRange=true,lineOfSight=true,uncharged=true}
        end),
        scenario("combat_victory_rewards_and_continue",404,{enemyHP=1},function(data,battle,_,enemy,encounter)
            local scrap,coal,xp=data.scrap,data.resources.coal,data.stats.xp
            shoot(enemy)
            assert(enemy.hp==0 and battle.finished=="win" and encounter.resolved,"real attack did not finish and resolve the encounter")
            assert(data.scrap>scrap and data.resources.coal>coal and data.stats.xp>xp,"victory did not award scrap, coal and XP")
            local awardedScrap,awardedCoal,awardedXP=data.scrap,data.resources.coal,data.stats.xp
            draw();control(ui.battleContinue)
            assert(game.state=="game" and game.scene=="stop" and game.battle==nil,"victory continue did not enter the settlement")
            for _=1,20 do update(.05) end
            assert(data.scrap==awardedScrap and data.resources.coal==awardedCoal and data.stats.xp==awardedXP,"victory rewards repeated after continuing")
            return {wonByAttack=true,scrap=awardedScrap-scrap,coal=awardedCoal-coal,xp=awardedXP-xp,rewardOnce=true}
        end),
        scenario("combat_defeat_health_and_return",405,{health=1},function(data,battle,player,_,encounter)
            local scrap,coal,xp=data.scrap,data.resources.coal,data.stats.xp
            control(ui.battleEnd)
            waitUntil(function() return battle.finished~=nil end,"enemy never completed the lethal attack")
            assert(player.hp==0 and battle.finished=="loss" and not encounter.resolved,"enemy attack did not produce a retryable defeat")
            assert(data.health==math.max(1,math.floor(data.maxHealth/2)),"defeat did not restore half player health")
            draw();control(ui.battleContinue)
            assert(game.state=="game" and game.scene=="train" and game.battle==nil,"defeat continue did not return to the train")
            assert(data.scrap==scrap and data.resources.coal==coal and data.stats.xp==xp,"defeat awarded victory rewards")
            return {defeatedByEnemy=true,health=data.health,returned=true,noVictoryReward=true}
        end),
        scenario("combat_retreat_preserves_encounter",406,{},function(data,_,player,_,encounter)
            local scrap,coal,xp,health=data.scrap,data.resources.coal,data.stats.xp,player.hp
            control(ui.battleRetreat)
            assert(game.state=="game" and game.scene=="train" and game.battle==nil,"retreat did not return to the train")
            assert(not encounter.resolved and data.encounters["2"]==encounter,"retreat removed the unresolved encounter")
            assert(data.health==health and data.scrap==scrap and data.resources.coal==coal and data.stats.xp==xp,"retreat changed health or awarded victory rewards")
            return {returned=true,retryable=true,noVictoryReward=true,healthPreserved=true}
        end),
    }
end

return {steps=steps}
