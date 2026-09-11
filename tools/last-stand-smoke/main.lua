local checks=0
local function expect(value,message)
    if not value then error(message,2) end
    checks=checks+1
end

local function run()
    local Catalog=require("game.catalog")
    local Quest=require("game.last_stand_quest")
    local Scene=require("game.last_stand_scene")
    local View=require("game.window_scene")
    local Gun=require("game.first_person_shooting")
    local Shootout=require("game.last_stand_shootout")
    local saves=0
    local data={version=33,location=4,scene="stop",stopped=true,health=20,maxHealth=20,
        equipment={},inventory={},inventoryCapacity=6,weaponDurability={},ammo={["22lr"]=0},
        scrap=5,goodwill=2,resources={food=3},character="missing-player.png",lastStand={},audio={sfxVolume=0}}
    local runtime={state="game",scene="stop",saveData=data,player={x=480,y=500,facing=1}}
    data.character="botanist-frog.png"
    local context={runtime=runtime,catalog=Catalog,width=960,height=720,
        characterImages={[data.character]=love.graphics.newImage("assets/sprites/MainCharacters/"..data.character)},
        writeSave=function() saves=saves+1; return true end}
    context.npcImages={["guard-fox.png"]=love.graphics.newImage("assets/sprites/NPCS/guard-fox.png")}
    local aidRoot="assets/sprites/props/first-aid/"
    local aid={}
    for name,file in pairs({wound="small-cut.png",disinfectant="disinfectant-bottle.png",rag="clean-rag.png",
        swab="ointment-swab.png",gauze="gauze-pad.png",bandage="bandage-roll.png"}) do
        aid[name]=love.graphics.newImage(aidRoot..file)
    end
    aid.bandageStrips={}
    for _,file in ipairs({"bandage-strip.png","bandage-strip-2.png","bandage-strip-3.png"}) do
        aid.bandageStrips[#aid.bandageStrips+1]=love.graphics.newImage(aidRoot..file)
    end
    context.scenery={firstAidAssets=aid}
    local quest=Quest.new(context)
    local canvas=love.graphics.newCanvas(960,720)
    local function draw(name)
        love.graphics.setCanvas({canvas,stencil=true})
        love.graphics.clear(0,0,0,1)
        quest:draw()
        love.graphics.setCanvas()
        if os.getenv("LAST_STAND_CAPTURE")=="1" then canvas:newImageData():encode("png",name..".png") end
    end

    -- Real keyboard movement must cover the same distance at 30 and 120 fps.
    local isDown=love.keyboard.isDown
    love.keyboard.isDown=function(key) return key=="d" end
    local positions={}
    for _,fps in ipairs({30,120}) do
        local scene=Scene.new("interior")
        scene.player.x=400; scene.player.y=350
        for _=1,fps do Scene.update(scene,1/fps) end
        positions[#positions+1]=scene.player.x
    end
    love.keyboard.isDown=isDown
    expect(math.abs(positions[1]-575)<.01 and math.abs(positions[2]-575)<.01,"keyboard movement depends on frame rate")
    expect(not Scene.isWalkable(Scene.new("interior"),220,430),"dining table has no collision")
    expect(not Scene.isWalkable(Scene.new("interior"),220,590),"player can walk through the front wall")
    expect(Scene.isWalkable(Scene.new("interior"),480,590),"back door route is blocked")

    -- Sparse inventories, broken firearms and real ammunition sources.
    local sparse={equipment={},inventory={[40]="frontier-22-lever-rifle"},ammo={["22lr"]=4},weaponDurability={}}
    expect(Gun.hasUsableFirearm(sparse,Catalog),"sparse inventory firearm not discovered")
    sparse.weaponDurability["frontier-22-lever-rifle"]=0
    expect(not Gun.hasUsableFirearm(sparse,Catalog),"broken firearm accepted")
    sparse.weaponDurability["frontier-22-lever-rifle"]=100
    local ownQuest={}
    local own=Gun.new(sparse,Catalog,ownQuest,960,720)
    expect(Gun.fire(own,sparse,ownQuest) and sparse.ammo["22lr"]==3,"personal ammunition was not consumed")
    expect(Gun.new(sparse,Catalog,ownQuest,960,720).magazine==3,"window switch refilled a personal magazine")
    local house=Gun.chooseWeapon(own,{name="frontier-22-lever-rifle",borrowed=true},sparse,Catalog,ownQuest)
    expect(house.borrowed and ownQuest.loanAmmo==48 and sparse.ammo["22lr"]==3,"voluntary loan changed personal ammo")
    own=Gun.chooseWeapon(house,{name="frontier-22-lever-rifle",borrowed=false},sparse,Catalog,ownQuest)
    expect(not own.borrowed and own.magazine==3,"weapon selection refilled a magazine or lost its ammo source")

    -- The supply shortcut must preserve the personal firearm it replaces.
    local supplyData={equipment={"compact-scrap-pistol"},inventory={},ammo={["9mm"]=20}}
    local supplyQuest={}
    local supplyBattle=Shootout.new(supplyQuest,supplyData,Catalog,"wide",960,720)
    local personal=supplyBattle.gun
    expect(Gun.fire(personal,supplyData,supplyQuest),"personal supply fixture could not fire")
    personal.cooldown=0
    local personalMagazine=personal.magazine
    expect(Shootout.supply(supplyBattle,supplyData,Catalog),"supply shortcut did not lend a weapon")
    expect(personal.weapon=="compact-scrap-pistol" and not personal.borrowed,
        "supply shortcut rewrote the cached personal firearm into the loan")
    local borrowed=supplyBattle.gun
    expect(Gun.fire(borrowed,supplyData,supplyQuest),"loan supply fixture could not fire")
    borrowed.cooldown=0
    local loanMagazine=borrowed.magazine
    supplyBattle.gun=Gun.chooseWeapon(borrowed,{name=personal.weapon,borrowed=false},supplyData,Catalog,supplyQuest)
    expect(supplyBattle.gun==personal and personal.magazine==personalMagazine and supplyData.ammo["9mm"]==19,
        "returning to a personal firearm lost its magazine or consumed the wrong ammunition")
    expect(Shootout.supply(supplyBattle,supplyData,Catalog),"supply shortcut did not reselect the house rifle")
    expect(supplyBattle.gun==borrowed and borrowed.magazine==loanMagazine and supplyQuest.loanAmmo==47,
        "reselecting a house rifle refilled its magazine or duplicated ammunition")
    supplyQuest.loanAmmo=0; borrowed.magazine=0
    expect(Shootout.supply(supplyBattle,supplyData,Catalog) and supplyQuest.loanAmmo==12
        and supplyBattle.gun.magazine>0,"depleted house supply did not provide a usable pouch")

    -- Android packages keep converted Ogg files instead of the source WAVs.
    Gun.release()
    local newSource,getInfo=love.audio.newSource,love.filesystem.getInfo
    local loadedReports,playedReports,releasedReports=0,0,0
    love.filesystem.getInfo=function(path) return path:match("%.ogg$") and {type="file"} or nil end
    love.audio.newSource=function(path)
        expect(path:match("%.ogg$"),"first-person audio requested a missing unconverted source file")
        loadedReports=loadedReports+1
        return {stop=function() end,setPitch=function() end,setVolume=function() end,
            play=function() playedReports=playedReports+1 end,
            release=function() releasedReports=releasedReports+1 end}
    end
    Gun.playReport("frontier-22-lever-rifle",Catalog,data,false)
    Gun.playReport("frontier-22-lever-rifle",Catalog,data,true)
    expect(loadedReports==1 and playedReports==2,"packaged weapon reports were silent or bypassed the cache")
    Gun.release()
    expect(releasedReports==1,"leaving the quest retained its cached weapon audio")
    love.audio.newSource,love.filesystem.getInfo=newSource,getInfo

    runtime.inventoryOpen=true
    expect(quest:update(.1)==false and not runtime.lastStand,"scout interrupted inventory")
    runtime.inventoryOpen=false
    quest:update(.01)
    expect(runtime.lastStand.mode=="approach","scout approach did not start")
    runtime.lastStand.scout.x=480; runtime.lastStand.scout.y=500
    runtime.dialogue={text="busy"}
    quest:update(1)
    expect(runtime.lastStand.mode=="approach","approaching scout interrupted dialogue")
    runtime.dialogue=nil
    quest:update(.6)
    expect(runtime.lastStand.mode=="offer","scout offer did not open")
    draw("01-offer")
    quest:keypressed("n")
    runtime.dialogue=nil
    quest:update(.1)
    quest:keypressed("e")
    expect(runtime.lastStand.mode=="offer","decline was not reversible at the same stop")
    quest:keypressed("y")
    expect(runtime.lastStand.mode=="escort","acceptance did not start escort")
    quest:keypressed("space")
    expect(runtime.lastStand.mode=="backyard","escort could not be skipped")
    draw("02-backyard")

    local function place(x,y)
        runtime.lastStand.scene.player.x=x; runtime.lastStand.scene.player.y=y
    end
    place(750,455)
    quest:keypressed("e")
    expect(runtime.lastStand.treatment~=nil,"wounded treatment did not open")
    draw("09-first-aid")
    local getTreatmentPads=love.joystick.getJoysticks
    local treatmentButtons={a=true}
    love.joystick.getJoysticks=function() return {{isGamepad=function() return true end,
        isGamepadDown=function(_,button) return treatmentButtons[button] or false end,
        getGamepadAxis=function() return 0 end}} end
    quest:update(.01)
    expect(runtime.lastStand.treatment.phase==2,"controller A did not advance first aid")
    treatmentButtons.a=false; quest:update(.01)
    love.joystick.getJoysticks=getTreatmentPads
    quest:keypressed("return")
    local treatment=runtime.lastStand.treatment
    treatment.progress.rubDistance=219; treatment.progress.rubTurns=3
    treatment.dragging=true; treatment.previousPointer={x=450,y=370}
    quest:keypressed("p")
    quest:mousemoved(520,370)
    expect(treatment.phase==3 and treatment.progress.rubDistance==219,
        "pointer motion advanced first aid while paused")
    quest:mousereleased(520,370,1)
    expect(not treatment.dragging,"releasing while paused left a treatment gesture held")
    quest:keypressed("p")
    for _=1,4 do quest:keypressed("return") end
    expect(data.lastStand.woundedTreated and not runtime.lastStand.treatment,"first aid did not complete")
    place(480,360); quest:keypressed("e")
    expect(runtime.lastStand.mode=="interior","back door did not enter interior")
    draw("03-interior")
    local drawEffect,drawActor=View.drawEffect,View.drawActor
    local interiorFlashes,interiorTargets=0,0
    View.drawEffect=function() interiorFlashes=interiorFlashes+1 end
    View.drawActor=function() interiorTargets=interiorTargets+1 end
    View.drawInterior({},.05,960,720,1,0,false,true)
    expect(interiorFlashes==0 and interiorTargets==1,"reduced flashes did not suppress interior enemy gunfire")
    interiorTargets=0
    View.drawInterior({victory=true},.05,960,720,1,0,false,false)
    expect(interiorFlashes==0 and interiorTargets==0,"defeated enemies reappeared before the reward conversation")
    View.drawEffect,View.drawActor=drawEffect,drawActor
    local enlarged=love.graphics.newCanvas(1440,1080)
    love.graphics.setCanvas({enlarged,stencil=true})
    love.graphics.clear(0,0,0,1)
    love.graphics.push("all")
    love.graphics.scale(1.5,1.5)
    quest:draw()
    love.graphics.pop()
    love.graphics.setCanvas()
    local smallPixels,bigPixels=canvas:newImageData(),enlarged:newImageData()
    local r1,g1,b1=smallPixels:getPixel(360,195)
    local r2,g2,b2=bigPixels:getPixel(540,292)
    expect(math.abs(r1-r2)+math.abs(g1-g2)+math.abs(b1-b2)<.3,"interior window layers ignore viewport scaling")
    if os.getenv("LAST_STAND_CAPTURE")=="1" then bigPixels:encode("png","08-interior-scaled.png") end
    place(300,335); quest:keypressed("e")
    expect(data.lastStand.loanActive and data.lastStand.loanAmmo==48,"fox rifle loan was not granted")
    expect(next(data.equipment)==nil and next(data.inventory)==nil,"loan entered permanent inventory")
    expect(View.backgroundPath({quest=data.lastStand}):find("stop%-04%-"),"view does not use origin stop")
    expect(View.backgroundPath({originStop=21})==View.backgroundPath({originStop=4}),"background route mapping is inconsistent")

    for _,windowId in ipairs({"wide","tall"}) do
        local layout=View.layout(windowId,960,720)
        for index in ipairs(View.slots) do
            local x,y=View.slotPosition(layout,index)
            expect(not View.buildingSolid(layout,x,y),"target slot is on a solid wall: "..index)
            expect(View.targetHit(layout,index,x,y),"target center cannot be hit")
        end
        expect(not View.pointOpen(windowId,960,720,0,0),"outside-frame alpha counted as window")
    end

    local function takeWindow(x,y)
        place(x,y); quest:keypressed("e")
        expect(runtime.lastStand.handoff~=nil,"defender did not hand off the window")
        quest:update(.8)
    end
    takeWindow(350,285)
    expect(runtime.lastStand.mode=="shootout","wide window did not start shootout")
    local battle=runtime.lastStand.shootout
    local x,y=View.slotPosition(View.layout("wide",960,720),1)
    battle.targets[1].status="exposed"; battle.targets[1].timer=2
    quest:mousemoved(x,y)
    quest:mousepressed(x,y,2)
    expect(battle.gun.ads,"ADS did not engage")
    draw("04-wide-ads")
    quest:mousereleased(x,y,2)
    quest:mousepressed(x,y,1)
    expect(data.lastStand.kills==1 and data.lastStand.loanAmmo==47,"target hit or loan ammunition debit failed")
    expect(battle.targets[1].status=="dying","target skipped its death animation")
    quest:update(.1)
    expect(battle.gun.weaponX>battle.gun.aimX and battle.gun.weaponY>battle.gun.aimY,"hip-fire offset is not below-right")
    draw("05-wide-hipfire")
    local magazine=battle.gun.magazine
    quest:keypressed("escape")
    takeWindow(660,285)
    battle=runtime.lastStand.shootout
    expect(battle.windowId=="tall" and battle.gun.magazine==magazine,"switching windows lost magazine state")
    expect(battle.targets[1].status=="dying","switching windows reset the enemy pool")
    draw("06-tall-hipfire")
    quest:focus(false)
    local pauseTime=data.lastStand.holdElapsed
    quest:update(5)
    expect(data.lastStand.holdElapsed==pauseTime,"lost focus did not pause combat")
    quest:keypressed("p")
    local getPads=love.joystick.getJoysticks
    local buttons={start=true}
    local axes={rightx=.5}
    local pad={isGamepad=function() return true end,isGamepadDown=function(_,key) return buttons[key] or false end,
        getGamepadAxis=function(_,key) return axes[key] or 0 end}
    love.joystick.getJoysticks=function() return {pad} end
    quest:update(.02)
    expect(runtime.lastStand.paused,"controller Start did not pause")
    buttons.start=false; quest:update(.02)
    buttons.start=true; quest:update(.02)
    expect(not runtime.lastStand.paused,"controller Start did not resume")
    local aimBefore=battle.gun.aimX
    buttons.start=false; quest:update(.02)
    expect(battle.gun.aimX>aimBefore,"right stick did not aim")
    quest:mousepressed(battle.gun.aimX,battle.gun.aimY,2)
    quest:update(.02)
    expect(battle.gun.ads,"an idle connected gamepad cancelled mouse aiming")
    quest:mousereleased(battle.gun.aimX,battle.gun.aimY,2)
    axes.triggerleft=1; quest:update(.02)
    expect(battle.gun.ads,"controller left trigger did not engage aiming")
    axes.triggerleft=0; quest:update(.02)
    expect(not battle.gun.ads,"releasing the controller trigger left aiming engaged")
    quest:touchpressed("ads",320,646)
    quest:touchreleased("ads",320,646)
    quest:update(.02)
    expect(battle.gun.ads,"an idle connected gamepad cancelled touch aiming")
    quest:touchpressed("ads",320,646); quest:touchreleased("ads",320,646)
    love.joystick.getJoysticks=getPads
    quest:keypressed("c")
    local hold=data.lastStand.holdElapsed
    local integrity=data.lastStand.positionIntegrity
    local coveredHealth=data.health
    for _=1,80 do quest:update(.05) end
    expect(data.lastStand.holdElapsed==hold and data.lastStand.positionIntegrity==integrity,"cover grants progress or takes unavoidable damage")
    expect(battle.coverProgress==1 and data.health==coveredHealth,"cover did not lower the view or protect player health")
    expect(not Shootout.fire(battle,data,960,720,Catalog),"player could fire below the window")
    draw("10-crouched-cover")
    quest:keypressed("c")
    quest:update(.05)
    expect(battle.coverProgress>0 and battle.coverProgress<1,"returning to the window did not animate")
    expect(not Shootout.fire(battle,data,960,720,Catalog),"player could fire before rising to the window")
    for _=1,6 do quest:update(.05) end

    -- A real enemy shot damages and saves the player's persistent health.
    local enemyRandom=love.math.random
    love.math.random=function() return 0 end
    battle.targets[1].status="firing"; battle.targets[1].timer=.16; battle.targets[1].fired=false
    battle.targets[1].heavy=false; battle.hitRecovery=0
    local healthBefore,savesBefore=data.health,saves
    quest:update(.01)
    love.math.random=enemyRandom
    expect(data.health==healthBefore-1 and saves>savesBefore,"enemy hit did not damage and save actual player health")
    draw("11-exposed-hit")

    -- An independent aiming finger never fires; the FIRE finger preserves aim.
    battle.gun.cooldown=0
    local gripX,gripY=require("game.mobile_weapon_aim").gripForAim(battle.gun.weapon,battle.gun.ads and "sights" or "hip",x,y,960,720)
    quest:touchpressed("aim",gripX,gripY)
    draw("12-touch-grip-hip")
    local rounds=data.lastStand.loanAmmo
    quest:touchpressed("fire",875,646)
    expect(data.lastStand.loanAmmo==rounds-1,"touch fire button did not shoot")
    expect(math.abs(battle.gun.aimX-x)<.001 and math.abs(battle.gun.aimY-y)<.001,"fire button moved the crosshair")
    quest:touchmoved("fire",890,648)
    expect(math.abs(battle.gun.aimX-x)<.001,"fire finger moved aim while dragging")
    quest:touchreleased("fire",875,646)
    battle.gun.cooldown=0
    local secondRounds=data.lastStand.loanAmmo
    quest:touchpressed("second-fire",gripX+90,gripY)
    expect(data.lastStand.loanAmmo==secondRounds-1,"second canvas finger did not fire")
    quest:touchmoved("second-fire",gripX+120,gripY+30)
    expect(math.abs(battle.gun.aimX-x)<.001 and math.abs(battle.gun.aimY-y)<.001,"second canvas finger stole aim")
    quest:touchreleased("second-fire",gripX+90,gripY)
    quest:touchreleased("aim",gripX,gripY)
    expect(runtime.lastStand.aimTouch==nil,"released aiming touch retained ownership")
    quest:touchpressed("focus-aim",gripX,gripY)
    quest:focus(false)
    expect(runtime.lastStand.aimTouch==nil and runtime.lastStand.paused,"focus loss retained aiming touch")
    quest:keypressed("escape")
    quest:touchpressed("cover-button",440,646); quest:touchreleased("cover-button",440,646)
    for _=1,6 do quest:update(.05) end
    expect(battle.ducking and battle.coverProgress==1,"mobile COVER button did not crouch")
    draw("13-mobile-cover")
    local originalWindow=battle.windowId
    battle.windowId="wide"; draw("13-mobile-cover-wide"); battle.windowId=originalWindow
    quest:touchpressed("cover-button",440,646); quest:touchreleased("cover-button",440,646)
    for _=1,6 do quest:update(.05) end
    quest:touchpressed("ads",320,646); quest:touchreleased("ads",320,646)
    draw("14-touch-grip-sights")
    quest:touchpressed("ads",320,646); quest:touchreleased("ads",320,646)

    -- Loading an active battle safely restores the interior and its progress.
    local savedHold=data.lastStand.holdElapsed
    local savedMagazine=battle.gun.magazine
    local savedLoanAmmo=data.lastStand.loanAmmo
    local Save=require("game.save")
    expect(Save.write(99,data),"active defense could not be written through the save schema")
    local loaded=Save.read(99)
    expect(loaded and loaded.lastStand.weaponSession.magazine==savedMagazine
        and loaded.lastStand.loanAmmo==savedLoanAmmo,"serialized save lost magazine or borrowed ammunition")
    expect(loaded.health==data.health,"serialized save lost enemy hit damage")
    Save.remove(99)
    data=loaded; runtime.saveData=data
    runtime.lastStand=nil
    quest=Quest.new(context)
    quest:update(.01)
    expect(runtime.lastStand.mode=="interior" and math.abs(data.lastStand.holdElapsed-savedHold)<.000001,
        "save/resume lost battle progress")
    place(480,620); quest:keypressed("e")
    place(480,605); quest:keypressed("e")
    expect(not runtime.lastStand and data.lastStand.state=="paused","safe return did not pause the quest")
    expect(not data.lastStand.loanActive and data.lastStand.loanAmmo==0,"loan escaped to the stop")
    runtime.dialogue=nil
    quest:update(.01)
    runtime.lastStand.scout.x=480; runtime.lastStand.scout.y=500
    quest:update(.6); quest:keypressed("e")
    expect(runtime.lastStand.mode=="backyard","paused quest could not resume")
    place(480,360); quest:keypressed("e")
    takeWindow(350,285)
    quest:keypressed("l")

    -- Exercise the entire real-time state machine, including reloads, target
    -- tells/deaths, all phases, and visible withdrawal; no forced victory state.
    local frames,withdrawal=0,false
    local breaks={}
    while not data.lastStand.victory and frames<6500 do
        if runtime.lastStand.mode=="interior" then
            local phase=data.lastStand.intermission
            expect(phase~=nil,"battle returned to the room without a phase break")
            breaks[phase]=(breaks[phase] or 0)+1
            local previousHold,previousIntegrity=data.lastStand.holdElapsed,data.lastStand.positionIntegrity
            quest:update(20)
            expect(data.lastStand.holdElapsed==previousHold and data.lastStand.positionIntegrity==previousIntegrity,
                "intermission advanced combat or damaged the house")
            takeWindow(350,285)
        end
        battle=runtime.lastStand.shootout
        if Gun.needsSupply(battle.gun,data,data.lastStand) then quest:keypressed("l") end
        if battle.gun.magazine==0 and battle.gun.reloadTimer==0 then quest:keypressed("r") end
        local incoming=false
        for _,target in ipairs(battle.targets) do
            if target.status=="firing" or (target.status=="exposed" and target.timer<.35) then incoming=true end
        end
        if battle.ducking~=incoming then quest:keypressed("c") end
        if data.lastStand.kills<15 and battle.gun.cooldown==0 then
            for index,target in ipairs(battle.targets) do
                if target.status=="exposed" then
                    x,y=View.slotPosition(View.layout(battle.windowId,960,720),index)
                    quest:mousepressed(x,y,1)
                    break
                end
            end
        end
        quest:update(.05)
        if runtime.lastStand.mode=="shootout" and battle.result=="withdrawing" then withdrawal=true end
        frames=frames+1
    end
    expect(runtime.lastStand.mode=="interior" and data.lastStand.victory,
        string.format("full battle did not return to surviving residents: mode=%s hold=%.2f kills=%d morale=%.2f integrity=%.2f recoveries=%d phase=%s frames=%d",
            runtime.lastStand.mode,data.lastStand.holdElapsed,data.lastStand.kills,data.lastStand.enemyMorale,
            data.lastStand.positionIntegrity,data.lastStand.recoveries or 0,tostring(data.lastStand.intermission),frames))
    expect(breaks[2]==1 and breaks[3]==1,"authored intermissions were missing or repeated")
    expect(data.lastStand.holdElapsed>=180 and data.lastStand.kills>=15,"victory bypassed hold/kill requirements")
    expect(withdrawal,"enemy withdrawal was skipped")
    expect(data.scrap==5 and not data.lastStand.rewardClaimed,"reward was granted before residents were checked")
    place(300,335); quest:keypressed("e")
    expect(not data.lastStand.rewardClaimed,"fox granted reward before the resident check")
    place(710,335); quest:keypressed("e")
    expect(data.lastStand.residentChecked,"post-battle resident conversation was not remembered")
    place(300,335); quest:keypressed("e")
    expect(runtime.lastStand.mode=="aftermath","fox did not resolve the completed defense")
    expect(data.scrap==5+data.lastStand.rewardScrap and data.goodwill==5 and data.resources.food==5,"victory reward was incorrect")
    expect(not data.lastStand.loanActive and data.lastStand.loanAmmo==0,"loan was not reclaimed")
    draw("07-aftermath")
    quest:keypressed("t")
    expect(runtime.lastStand.mode=="interior","stay choice did not restore the walkable house")
    place(350,285); quest:keypressed("e")
    expect(not runtime.lastStand.handoff,"a completed battle could be restarted")
    place(300,335); quest:keypressed("e")
    expect(data.scrap==5+data.lastStand.rewardScrap,"repeat conversation duplicated the reward")
    place(480,620); quest:keypressed("e")
    place(480,605); quest:keypressed("e")
    local texturesBeforeReturn=love.graphics.getStats().texturememory
    quest:keypressed("space")
    expect(not runtime.lastStand and data.lastStand.completed,"return did not complete the quest")
    expect(love.graphics.getStats().texturememory<texturesBeforeReturn,
        "returning to the stop retained the quest's scene and weapon textures")
    local scrap=data.scrap
    runtime.dialogue=nil; quest:update(.1)
    expect(not runtime.lastStand and data.scrap==scrap,"completed quest respawned or repeated its reward")
    local fallbackQuest={holdElapsed=123,kills=8,enemyMorale=45,positionIntegrity=0,
        phaseCheckpoint=105,loanActive=true,loanAmmo=12}
    local fallback=Shootout.new(fallbackQuest,data,Catalog,"wide",960,720)
    Shootout.retry(fallback)
    expect(fallbackQuest.holdElapsed==105 and fallbackQuest.kills==8 and fallbackQuest.positionIntegrity==65,
        "fallback did not preserve earlier phases and eliminations")
    local function measurePressure(morale)
        love.math.setRandomSeed(14641)
        local pressureQuest={holdElapsed=110,kills=0,enemyMorale=morale,positionIntegrity=100,
            phaseCheckpoint=105,completedPhase=2,loanActive=true,loanAmmo=200}
        local pressureData={health=200,maxHealth=200,equipment={},inventory={},ammo={},audio={sfxVolume=0}}
        local pressureBattle=Shootout.new(pressureQuest,pressureData,Catalog,"wide",960,720)
        for _=1,600 do Shootout.update(pressureBattle,.05,pressureData,Catalog,960,720) end
        return pressureBattle,pressureQuest
    end
    local highPressure,highQuest=measurePressure(100)
    local lowPressure,lowQuest=measurePressure(0)
    expect(lowPressure.enemyShots>0,"low morale froze all enemy activity before the hold requirement")
    expect(highPressure.enemyShots>lowPressure.enemyShots*2,"low morale did not meaningfully reduce incoming fire")
    expect(lowQuest.positionIntegrity>highQuest.positionIntegrity,"reduced enemy fire did not relieve position pressure")
    expect(not lowPressure.result and lowQuest.kills==0,"zero morale bypassed the hold or elimination requirements")
    expect((data.lastStand.recoveries or 0)==0,"minimum-elimination defense still entered the recovery loop")

    -- Resolve real enemy firing states with known rolls: misses, hits, cover,
    -- simultaneous fire and a forced retreat must all affect the same health.
    for _,windowId in ipairs({"wide","tall"}) do
        local hitData={health=20,maxHealth=20,equipment={},inventory={},ammo={},audio={sfxVolume=0}}
        local hitQuest={loanActive=true,loanAmmo=48}
        local hitBattle=Shootout.new(hitQuest,hitData,Catalog,windowId,960,720)
        local originalRandom=love.math.random
        local function shot(roll,dt,heavy)
            for _,target in ipairs(hitBattle.targets) do target.status="hidden"; target.timer=999 end
            local target=hitBattle.targets[1]
            target.status="firing"; target.timer=.16; target.fired=false; target.heavy=heavy
            love.math.random=function() return roll end
            Shootout.update(hitBattle,dt,hitData,Catalog,960,720)
            love.math.random=originalRandom
        end
        shot(.99,.01,false)
        expect(hitData.health==20 and hitQuest.positionIntegrity<100,"exposed enemy shots never miss")
        shot(0,.01,false)
        expect(hitData.health==19,"exposed shot did not damage actual health")
        shot(0,.01,true)
        expect(hitData.health==19,"simultaneous shots bypassed the hit recovery interval")
        Shootout.setCover(hitBattle,true)
        local safeIntegrity=hitQuest.positionIntegrity
        shot(0,1,true)
        expect(hitData.health==19 and hitQuest.positionIntegrity==safeIntegrity and hitBattle.coverProgress==1,
            "crouching failed to shield health and the firing position")
        Shootout.setCover(hitBattle,false)
        shot(0,.01,true)
        expect(hitData.health==19 and hitBattle.coverProgress>0 and hitBattle.coverProgress<1,
            "enemy hit the player before the view had risen above cover")
        shot(0,.3,true)
        expect(hitData.health==17 and hitBattle.coverProgress==0,"heavy enemy fire did not damage an exposed player")
        hitData.health=2
        shot(0,1,true)
        expect(hitData.health==1 and hitBattle.result=="retreat" and hitBattle.retreatReason=="wounded",
            "critical wounds did not safely pull the player from the window")
        Shootout.retry(hitBattle)
        expect(hitData.health==1 and not hitBattle.result,"regrouping silently healed the player")
    end
    print(string.format("LAST_STAND_PRESSURE_OK high_morale_shots=%d low_morale_shots=%d recoveries=%d",
        highPressure.enemyShots,lowPressure.enemyShots,data.lastStand.recoveries or 0))
    print(string.format("LAST_STAND_FOCUS_OK checks=%d saves=%d kills=%d hold=%.2f scrap=%d",checks,saves,data.lastStand.kills,data.lastStand.holdElapsed,data.scrap))
end

function love.load()
    local ok,err=xpcall(run,debug.traceback)
    if not ok then io.stderr:write("LAST_STAND_FOCUS_ERROR: "..tostring(err).."\n"); io.stderr:flush() end
    love.event.quit(ok and 0 or 1)
end
