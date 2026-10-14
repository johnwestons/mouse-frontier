-- Real applications/ENet with isolated saves and normal guest trade inputs.
io.stdout:setvbuf('no')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE')
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local scene=assert(os.getenv('MOUSE_FRONTIER_TRADE_SCENE'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Viewport=require('game.viewport'); local Catalog=require('game.catalog')
local Items=require('game.item_instances'); local Entities=require('game.coop_entities')
local app,c,started,finished,stage,capture; local captured={}; local connections=0; local generation
local steps,stepIndex,request,submitted,lastTrade,originalHostItem,originalGuestItem,purchasedItem,expectedScrap,initialAmmo
local firstLeave,rejoinAt,restoreWrite,saveRetried
local function check(value,message) assert(value,message) end
local function press(rect)
    check(rect,'missing trade control'); local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('trade-test',x,y); app.touchreleased('trade-test',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name])
    if text then app.textinput(text); app.keypressed('return'); app.keyreleased('return') end
end
local function openMenu() app.keypressed('f8'); app.keyreleased('f8'); app.draw() end
local function finish()
    if finished then return end; finished=true
    if restoreWrite then love.filesystem.write=restoreWrite; restoreWrite=nil end
    check(app.quit()~=true,'quit was cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true trade='..scene..' reconnect=true input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(8112026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    check(c and c.ui.localPlay,'application Local Play missing'); local lp=c.ui.localPlay
    lp.context.bind='127.0.0.1'
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99); check(c.enterGame(c.newSave(c.characters[1])),'fixture campaign failed')
        local data=c.runtime.saveData; data.scrap=200
        if scene=='stop' then
            data.location=20; c.runtime.scene='stop'; data.scene='stop'
            local layout=c.ensureStopLayout(); layout.npcOutside='crow-merchant.png'; layout.npc='crow-merchant.png'
            layout.npcOffers=layout.npcOffers or {}; layout.npcOffers['crow-merchant.png']='trade'
            layout.tradeStock={'frontier-short-sword','field-bandage-roll','rocks'}; layout.tradeBudget=100
            c.setupNPC(); c.runtime.npcActor.x=600; c.runtime.npcActor.y=430
            c.runtime.player.x=550; c.runtime.player.y=430
        else
            local Caravans=require('game.crow_caravans'); local root=data.crowCaravans
            data.location=root.scheduledStops[1]; local camp=assert(Caravans.ensureCamp(data,Catalog,data.location))
            assert(require('game.crow_caravan_area').enter(data,data.location,{x=550,y=430}))
            local merchant=assert(Caravans.merchant(camp,'packmaster'))
            merchant.listings={{id='native-food',item='field-bandage-roll',quantity=1,basePrice=6},
                {id='native-gear',item='frontier-short-sword',quantity=1,basePrice=13},
                {id='native-ammo',item='rocks',quantity=1,basePrice=4,delivery='ammo'}}
            camp.resaleBudgetBase=100; camp.resaleBudgetSpent=0
            data.droppedItems[#data.droppedItems+1]={name='mailbox-reward',scene='train',carIndex=1,x=400,y=430,
                mailbox=true,permanent=true,storage={}}
            c.runtime.scene='caravan'; data.scene='caravan'; c.runtime.npcActor=nil
            c.runtime.player.x=286; c.runtime.player.y=430
        end
        data.playerX=c.runtime.player.x; data.playerY=c.runtime.player.y
        check(Entities.ensure(data) and Items.ensure(data),'merchant fixture invalid')
        originalHostItem=data.players.host.itemSlots.equipment[1].id
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(campaign)
            local ok,reason=place(campaign); if not ok then return ok,reason end
            local actor=campaign.players.companion
            actor.playerX=scene=='stop' and 550 or 286; actor.playerY=430; actor.inventory={[1]='frontier-short-sword'}
            if scene=='caravan' then for index=2,actor.inventoryCapacity do actor.inventory[index]='cowboy-hat' end end
            check(Items.ensure(campaign),'guest fixture identity failed'); return true
        end
        openMenu(); click('port',port); click('host'); check(lp.network,'could not start host')
        if not lp.menuOpen then openMenu() end
        stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil
        openMenu(); click('address','127.0.0.1:'..port); click('name','Trade test friend'); click('next'); click('join'); stage='joining'
    end
end
local function buyStep(index,captureName,verify)
    return {name='merchant.buy',capture=captureName,run=function(view)
        local selected=index
        if type(index)=='string' then
            selected=nil
            for slot,listing in ipairs(view.trade:source().stock) do if listing.id==index then selected=slot; break end end
            check(selected,'stable listing disappeared')
        end
        if touch then press(view.ui.tradeBuy[selected])
        elseif selected==1 and stepIndex==1 then app.gamepadpressed({},'a')
        else press(view.ui.tradeBuy[selected]) end
        check(view.trade.quote,'buy did not open confirmation'); app.draw()
        capture='guest-trade-confirm.png'
    end,confirm=true,verify=verify}
end
local function plan()
    if scene=='stop' then return {
        buyStep(1,'guest-stop-purchased.png',function(actor,result)
            purchasedItem=actor.itemSlots.inventory[2].id; check(result.details.delivery=='inventory','stop purchase destination wrong') end),
        {name='merchant.sell',run=function(view) press(view.ui.tradeSell[1]) end,verify=function(actor,result)
            check(not actor.inventory[1] and result.details.item=='frontier-short-sword','stop personal sale failed') end},
        buyStep(2,nil,function(actor) check(actor.inventory[1]=='field-bandage-roll','stop supply purchase failed') end),
        buyStep(3,'guest-stop-traded.png',function(actor,result)
            check(actor.inventory[3]=='rocks' and result.details.delivery=='inventory','stop ammo purchase parity failed') end),
    } end
    return {
        buyStep('native-ammo','guest-caravan-ammo.png',function(actor,result)
            check(result.details.delivery=='ammo' and actor.ammo.rocks==initialAmmo+Catalog.ammoPickupAmounts.rocks,'caravan direct ammo failed') end),
        buyStep('native-food','guest-caravan-mailbox.png',function(_,result) check(result.details.delivery=='train','full pack purchase did not reach mailbox') end),
        {name='merchant.sell',run=function(view) press(view.ui.tradeSell[1]) end,verify=function(actor) check(not actor.inventory[1],'caravan sale failed') end},
        {name='merchant.buy',run=function(view)
            local selected
            for index,listing in ipairs(view.trade:source().stock) do
                if listing.instances and listing.instances[1] and listing.instances[1].id==originalGuestItem then selected=index; break end
            end
            check(selected,'resale instance disappeared')
            if not view.ui.tradeBuy[selected] then press(view.ui.tradeBuyNext); app.draw() end
            press(view.ui.tradeBuy[selected]); app.draw()
            check(view.trade.quote,'resale confirmation missing'); capture='guest-resale-confirm.png'
        end,confirm=true,verify=function(actor)
            check(actor.itemSlots.inventory[1].id==originalGuestItem,'caravan buyback changed identity')
        end,capture='guest-resale-returned.png'},
        buyStep('native-gear','guest-caravan-traded.png',function(_,result) check(result.details.delivery=='train','full pack gear delivery failed') end),
    }
end
local function update(dt)
    if finished then return end; check(love.timer.getTime()-started<70,'trade smoke deadline exceeded'); app.update(math.min(.05,dt))
    local lp=c.ui.localPlay; local now=love.timer.getTime()
    -- These owned hidden instances receive injected controls. Concurrent smoke
    -- windows must not steal their logical input focus; real focus transitions
    -- have separate session/guest-view behavior coverage.
    if lp.focused==false then app.focus(true) end
    if role=='host' then
        if lp:pending() then click('approve'); if not lp.menuOpen then openMenu() end end
        local link=lp.network and lp.network.link
        if link and link.admitted and generation~=link.generation then
            connections=connections+1; generation=link.generation
            if connections==1 then
                restoreWrite=love.filesystem.write
                love.filesystem.write=function(path,bytes)
                    local data=c.runtime.saveData
                    local traded=scene=='stop' and data.stopLayouts[tostring(data.location)].tradeStock[1]==nil
                        or scene=='caravan' and (data.crowCaravans.trades or 0)>0
                    if path==Save.path(99) and traded then return false,'injected trade checkpoint failure' end
                    return restoreWrite(path,bytes)
                end
            end
        end
        if restoreWrite and lp.authority.pendingSave then
            capture='host-trade-save-retry.png'; stage='save-retry'
        end
        if stage=='save-retry' and captured['host-trade-save-retry.png'] then
            love.filesystem.write=restoreWrite; restoreWrite=nil
            if touch then press({x=190,y=438,w=185,h=58}) else app.keypressed('r') end
            check(not lp.authority.pendingSave,'trade checkpoint retry failed'); saveRetried=true; stage='hosting'
        end
        if connections==1 and not link then
            firstLeave=true; local saved=assert(Save.read(99)); local own=saved.players.companion
            check(saveRetried and saved.players.host.itemSlots.equipment[1].id==originalHostItem,'host ownership/save retry failed')
            check(saved.location==c.runtime.saveData.location and saved.scene==scene,'trade progressed journey')
            if scene=='stop' then check(own.inventory[1]=='field-bandage-roll' and own.inventory[2]=='frontier-short-sword' and own.inventory[3]=='rocks','stop trade save failed')
            else check(saved.crowCaravans.trades==5 and own.inventory[1]=='frontier-short-sword','caravan history save failed') end
        elseif connections==2 and not link then check(firstLeave,'guest did not leave between joins'); finish() end
    else
        if lp.error then error('Local Play failed: '..lp.error) end
        if stage=='joining' and lp.phase=='connected' and lp.clientView and lp.clientView.ready
            and lp.motionFrame and lp.motionFrame.ready and not lp.motionFrame.paused then
            click('close'); local view=lp.clientView; originalGuestItem=view.runtime.saveData.itemSlots.inventory[1].id
            expectedScrap=view.runtime.saveData.scrap; initialAmmo=view.runtime.saveData.ammo.rocks
            capture='guest-merchant-world.png'; stage='world-ready'
        elseif stage=='world-ready' and captured['guest-merchant-world.png'] and lp.clientView:inputAllowed() then
            local view=lp.clientView
            app.draw(); check(view:actionLabel()=='TRADE','merchant not reachable')
            if touch then local p=view.mobile.primary; press({x=p.x-15,y=p.y-15,w=30,h=30}) else app.keypressed('e') end
            check(view.runtime.tradeOpen and not view.runtime.inventoryOpen,'guest interact did not open trade')
            steps=plan(); stepIndex=1; capture='guest-trading.png'; stage='trading'
        elseif stage=='trading' and captured['guest-trading.png'] then
            local view=lp.clientView; local entry=steps[stepIndex]
            if request then
                local result=lp.network.lastCommandResult
                if result and result.requestId==request then
                    check(result.ok,'trade rejected: '..tostring(result.reason))
                    if not view.trade.pending then
                        check(result.durable and result.command==entry.name,'trade lacked durable result')
                        expectedScrap=expectedScrap+(entry.name=='merchant.sell' and result.details.price or -result.details.price)
                        check(view.runtime.saveData.scrap==expectedScrap,'scrap charged more than once')
                        entry.verify(view.runtime.saveData,result); capture=entry.capture; stepIndex=stepIndex+1; request=nil; lastTrade=now
                    end
                end
            elseif submitted then
                if not capture and view.trade.quote then
                    app.draw()
                    if not touch and stepIndex==1 and scene=='stop' then app.gamepadpressed({},'a') else press(view.ui.guestTradeConfirm) end
                    check(view.trade.pending,'confirmation did not submit purchase'); request=view.trade.pending.id; submitted=nil
                end
            elseif not entry and not capture then
                view.trade:close(); openMenu(); click('leave'); stage='rejoin'; rejoinAt=now
            elseif entry and not capture and (not lastTrade or now-lastTrade>.6) and view:actionsAllowed() then
                app.draw()
                if stepIndex==5 and scene=='caravan' then press(view.ui.tradeBuyPrev); app.draw() end
                entry.run(view)
                if entry.confirm then submitted=true else check(view.trade.pending,'sale did not submit'); request=view.trade.pending.id end
            end
        elseif stage=='rejoin' and now-rejoinAt>.4 then openMenu(); click('join'); stage='resumed'
        elseif stage=='resumed' and lp.phase=='connected' then
            local own=lp.replica.data.players.companion
            check(lp.replica.data.scrap==expectedScrap and lp.replica.data.scene==scene,'reconnect lost trade or progressed story')
            if scene=='stop' then check(own.itemSlots.inventory[2].id==purchasedItem,'reconnect replaced purchased gear')
            else check(own.itemSlots.inventory[1].id==originalGuestItem and lp.replica.data.crowCaravans.trades==5,'reconnect replaced resale or history') end
            click('leave'); print('LAN_TRADE_OK role=guest scene='..scene..' durable=true identities=true hostOnlyStory=true'); finish()
        end
        if lp.error then error('Local Play failed: '..lp.error) end
    end
end
local function guarded(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then print('LAN_SMOKE_FAILED role='..role..' '..tostring(reason)); finished=true
        if restoreWrite then love.filesystem.write=restoreWrite end
        if c and c.ui.localPlay then c.ui.localPlay:stop() end; love.event.quit(1)
    end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw() if app and not finished then guarded(function()
    app.draw(); if capture then love.graphics.captureScreenshot(capture); captured[capture]=true; capture=nil end
end) end end
function love.focus(focused) if app then app.focus(focused) end end
