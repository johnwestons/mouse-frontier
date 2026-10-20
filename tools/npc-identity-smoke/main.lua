-- Real application/input validation with isolated APPDATA. Artificial arrival
-- fixtures skip unrelated route events; offers, hand-ins and saves use the app.
local app,c,routine,pending,finished
local checks,captures,reloads=0,0,0
local mobile=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local px,py=0,0
local function expect(ok,message) assert(ok,message);checks=checks+1 end
function love.errorhandler(message)
    print(debug.traceback(tostring(message),2));return function()return 1 end
end
local function run()
    love.math.setRandomSeed(10202026)
    love.keyboard.isDown=function()return false end
    love.mouse.getPosition=function()return px,py end
    package.loaded['game.smoke_playthrough']={install=function(value)c=value end}
    app=require('game.application_composition').new({engine=love});app.installSmoke();app.load()
    local g,ui=c.runtime,c.ui
    local I=require('game.npc_identity');local T=require('game.npc_targets')
    local NPCs=require('game.scene_npcs');local Save=require('game.save');local Schema=c.saveSchema
    local function step(t)for _=1,math.ceil(t/.025)do app.update(.025)end end
    local function draw()love.graphics.origin();app.draw()end
    local function screen(x,y)
        local ox,oy,sx,sy=require('game.viewport').transform(960,720);return ox+x*sx,oy+y*sy
    end
    local function tap(x,y)
        px,py=screen(x,y)
        if mobile then app.touchpressed('identity-tap',px,py);app.touchreleased('identity-tap',px,py)
        else app.mousepressed(px,py,1);app.mousereleased(px,py,1)end
        step(.05)
    end
    local function button(r)
        expect(r~=nil,'missing native button');tap(r.x+r.w/2,r.y+r.h/2)
    end
    local function capture(name)
        pending=name..'.png';coroutine.yield();expect(not pending,'screenshot failed')
    end
    local function clearDialogue()
        if g.dialogue then draw();button(ui.dialogueContinue)end
    end
    local function interact()
        draw()
        if mobile then local controls=c.getMobileControls();controls:_updateCornerLayout();tap(controls.primary.x,controls.primary.y)
        else app.keypressed('e');app.keyreleased('e');step(.05)end
    end
    local function load(data)
        g.selectedSlot=98
        local ok,reason=c.enterGame(data)
        expect(ok,'could not enter identity fixture: '..tostring(reason));c.setupNPC()
        c.presentationRuntime.resetCamera(true);step(.05)
        expect(require('game.coop_entities').ensure(g.saveData),'fixture entities unprepared')
        expect(require('game.item_instances').ensure(g.saveData),'fixture items unprepared')
    end
    local function checkpoint()
        expect(c.persistenceRuntime.checkpoint(),'checkpoint failed')
        local saved=Save.read(98);expect(saved~=nil,'named campaign did not save')
        reloads=reloads+1;load(saved);return g.saveData
    end
    local function atStop(stop,kind)
        local d=assert(Schema.copy(g.saveData))
        d.location=stop;d.scene='stop';d.stopped=true;d.activeHouseDoor=nil;d.lastStopDoor=nil
        d.playerX,d.playerY=require('game.settlements').clamp(480,500,stop)
        d.conversations.nextStop=99
        d.encounters[tostring(stop)]={hasMob=false,resolved=true,mobFiles={}}
        d.stopSludges[tostring(stop)]={}
        if kind then
            local file='tinker-fox.png'
            d.stopLayouts[tostring(stop)]={npcOutside=file,npcInside='mail-mouse.png',npc=file,
                npcOffers={[file]=kind},offerPolicyVersion=require('game.stop_help_progression').policyVersion,
                deliveryOffers=kind=='supplies' and {[file]='food'} or nil}
        end
        load(d)
    end
    local function approach(person)
        local actor
        for _,candidate in ipairs(NPCs.list(g.saveData,g.scene,g.saveData.activeHouseDoor))do
            if candidate.characterId==person.id then actor=candidate;break end
        end
        expect(actor~=nil,'reserved NPC missing from '..g.scene..' at '..g.saveData.location..': '..person.id)
        g.player.x,g.player.y=actor.x,actor.y+32;step(.05);draw()
        expect(ui.interaction and ui.interaction.kind=='npc','named NPC is not interactable')
        expect(ui.npcIdentityCard and ui.npcIdentityCard.id==person.id and ui.npcIdentityCard.textFits,'name card missing or clipped')
    end
    local function accept(kind)
        interact();expect(g.questOffer and g.questOffer.kind==kind,'named sender has no expected offer')
        draw();button(ui.questAccept)
        expect(not g.questOffer and g.dialogue,'offer was not accepted')
    end
    g.selectedSlot=98;Save.remove(98)
    local initial=c.newSave(c.characters[1]);initial.homeStop={};initial.scene='stop';initial.location=3
    initial.npcStates={};initial.stopLayouts={};initial.npcRoster={'tinker-fox.png','mail-mouse.png','scout-frog.png'}
    initial.resources={food=20,water=20,coal=20,oil=20};initial.maintenance.condition=100
    initial.conversations.nextStop=99
    load(initial);atStop(4,'mail')
    local sender=assert(I.get(g.saveData,'tinker-fox.png'));approach(sender)
    capture('sender-card');accept('mail')
    local mail=g.saveData.mailQuests[1];expect(mail and mail.senderId==sender.id and mail.recipientId,'mail lacks permanent people')
    local mailId,recipientName=mail.entityId,I.name(g.saveData,mail.recipientId)
    expect(g.dialogue.text:find(recipientName,1,true),'accepted mail does not name its recipient')
    capture('mail-task');clearDialogue();checkpoint()
    atStop(5,'supplies')
    local supplier=assert(I.get(g.saveData,'tinker-fox.png'))
    expect(supplier.id~=sender.id and supplier.name~=sender.name,'reused fox art shares its identity')
    approach(supplier);accept('supplies')
    local supply=g.saveData.supplyQuests[1];expect(supply and supply.senderId==supplier.id and supply.recipientId,'supply task lacks permanent people')
    local supplyId=supply.entityId;clearDialogue();checkpoint()
    atStop(6,'ride')
    local traveler=assert(I.get(g.saveData,'tinker-fox.png'));approach(traveler);accept('ride');clearDialogue()
    local passenger=g.saveData.passengers[1]
    expect(passenger and passenger.characterId==traveler.id,'boarding replaced the passenger identity')
    g.journeyLogOpen=true;draw();expect(ui.journeyLogBounds~=nil,'named journal missing');capture('named-journal');g.journeyLogOpen=false
    local train=assert(Schema.copy(g.saveData));train.scene='train';train.playerX=passenger.x;train.playerY=passenger.y+28
    load(train);draw()
    expect(ui.npcIdentityCard and ui.npcIdentityCard.name==traveler.name,'aboard passenger name changed')
    capture('passenger-card');checkpoint()
    expect(g.saveData.passengers[1].characterId==traveler.id and I.name(g.saveData,g.saveData.passengers[1])==traveler.name,'reload changed passenger identity')
    local function findQuest(id)
        for _,list in ipairs({g.saveData.mailQuests,g.saveData.supplyQuests})do
            for _,q in ipairs(list)do if q.entityId==id then return q end end
        end
        error('saved task disappeared')
    end
    mail=findQuest(mailId);atStop(mail.destination)
    mail=findQuest(mailId);draw()
    expect(I.name(g.saveData,mail.recipientId)==recipientName,'recipient was renamed on arrival')
    capture('recipient-directions')
    g.mapOpen=true;draw();capture('recipient-map');g.mapOpen=false
    approach(assert(I.get(g.saveData,mail.recipientId)));capture('recipient-card')
    for _=1,3 do if mail.complete then break end;interact();clearDialogue();mail=findQuest(mailId)end
    expect(mail.complete,'mail could not be delivered to the named recipient')
    supply=findQuest(supplyId);atStop(supply.destination);supply=findQuest(supplyId)
    if not supply.complete then
        approach(assert(I.get(g.saveData,supply.recipientId)));interact();clearDialogue()
        expect(findQuest(supplyId).complete,'supplies could not be delivered to the named recipient')
    end
    checkpoint()
    expect(findQuest(mailId).complete and findQuest(supplyId).complete,'reload lost delivery completion')
    expect(g.saveData.relationships[mail.recipientId].helpCount>=1,'recipient history did not record mail')
    g.journeyLogOpen=true;draw();capture('deliveries-complete')
    print('NPC_IDENTITY_SMOKE_OK mode='..(mobile and 'mobile' or 'desktop')..' checks='..checks..' screenshots='..captures..' reloads='..reloads)
end
function love.load()routine=coroutine.create(run)end
function love.update()
    if finished then love.event.quit(finished=='ok' and 0 or 1);return end
    local ok,err=coroutine.resume(routine)
    if not ok then print(debug.traceback(routine,tostring(err)));finished='error'
    elseif coroutine.status(routine)=='dead' then finished='ok'end
end
function love.draw()
    if app then app.draw()end
    if pending then love.graphics.captureScreenshot(pending);pending=nil;captures=captures+1 end
end
