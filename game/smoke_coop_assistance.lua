local Items=require("game.item_instances")
local Entities=require("game.coop_entities")
local Help=require("game.stop_help_progression")
local Quests=require("game.help_quest_session")
local Save=require("game.save")
local Viewport=require("game.viewport")
local WorldView=require("game.world_view")
local TrainView=require("game.train_view")
local UIStyle=require("game.ui_layout")
local Preferences=require("game.local_preferences")
local Accessibility=require("game.accessibility")
local Schema=require("game.save_schema")
local Smoke={}

function Smoke.steps(context)
    local game,ui=context.runtime,context.ui
    local serial=0
    local function tap(x,y)
        local ox,oy,sx,sy=Viewport.transform(960,720)
        x,y=ox+x*sx,oy+y*sy
        if context.mobileEnabled() then
            serial=serial+1; local id="smoke-assistance-"..serial
            love.touchpressed(id,x,y); love.touchreleased(id,x,y)
        else love.mousepressed(x,y,1); love.mousereleased(x,y,1) end
    end
    local function control(rect,radio)
        assert(rect,"assistance UI control was not drawn")
        local x,y=rect.x+rect.w/2,rect.y+rect.h/2
        if radio and not context.mobileEnabled() then
            local point=UIStyle.transformRectFor("radio",{x=90,y=62,w=780,h=610},{x=x,y=y,w=0,h=0})
            x,y=point.x,point.y
        end
        tap(x,y)
    end
    local function handle(item)
        local x,y=TrainView.toView(context.presentationRuntime.getTrainView(),item.x+31,item.y+31)
        tap(WorldView.toScreen(x,y))
    end
    local function fixture(run)
        local previous,slot=game.saveData,game.selectedSlot
        local random=love.math.getRandomState()
        local preferences=assert(Schema.copy(ui.localPreferences.values))
        local filesystemWrite=love.filesystem.write
        local ok,result=xpcall(function()
            game.selectedSlot=99; Save.remove(99)
            ui.optionsOpen=false; ui.escMenuOpen=false; ui.mobileMenuOpen=false; ui.radioOpen=false
            assert(context.enterGame(context.newSave(context.character)))
            context.presentationRuntime.resetCamera(true)
            return run(game.saveData)
        end,debug.traceback)
        love.filesystem.write=filesystemWrite
        if ui.checkpointStatus and ui.checkpointStatus().pending then assert(ui.retryCheckpoint()) end
        ui.closeDecoration(); game.editMode=false; ui.radioOpen=false
        ui.optionsOpen=false
        for _,field in ipairs({"audio","accessibility"}) do
            local target=ui.localPreferences.values[field]
            for key in pairs(target) do target[key]=nil end
            for key,value in pairs(preferences[field]) do target[key]=value end
        end
        ui.localPreferences.values.configured=preferences.configured
        assert(ui.localPreferences:save())
        Save.remove(99); assert(context.enterGame(previous)); game.selectedSlot=slot
        context.presentationRuntime.resetCamera(true); love.math.setRandomState(random)
        if not ok then error(result) end
        return result
    end
    return {
        {name="coop_replica_campaign_projection",action=function() return fixture(function(data)
            local Players=require("game.coop_players")
            local State=require("game.net.game_state")
            local Codec=require("game.net.codec")
            assert(Players.enroll(data,"host",context.character,context.catalog,{[context.character]=true}))
            local companion=data.players.companion
            companion.playerX=data.playerX+24; companion.playerY=data.playerY
            data.events.replicaSmoke={[0]=true,[4]=false}
            local producer,replica=State.producer(),State.replica()
            local baseline,reason=producer:capture(data); assert(baseline,reason)
            local bytes=assert(Codec.encode(baseline,{maxBytes=8388608,maxEntries=200000,maxStringBytes=8192,maxDepth=16}))
            assert(replica:apply(baseline))
            assert(replica:actor().character==companion.character and replica.data.events.replicaSmoke[0]==true
                and replica.data.events.replicaSmoke[4]==false)
            assert(replica.data.players.companion.itemSlots.equipment[1].id==companion.itemSlots.equipment[1].id)
            assert(not replica.data.accessibility and not replica.data.audio.musicVolume and not replica.data.coop.network)
            local before=love.filesystem.read(Save.path(99))
            local saved=Save.write(99,replica.data)
            assert(saved==false and love.filesystem.read(Save.path(99))==before,"received campaign changed a host save")
            data.resources.food=data.resources.food+1
            local delta=assert(producer:capture(data)); assert(delta.mode=="delta" and #delta.domains==1 and delta.domains[1].id=="train")
            assert(replica:apply(delta) and replica.data.resources.food==data.resources.food)
            return {ok=true,actors=2,domains=#baseline.domains,baselineBytes=#bytes,dirtyDomains=1,
                sparseNumericKeys=true,privateSettingsExcluded=true,guestSaveDenied=true,input="live initialized campaign projection"}
        end) end,check=function(_,_,_,result) return result and result.ok end},
        {name="party_scene_travel_save_resume",action=function() return fixture(function(data)
            local Players=require("game.coop_players")
            assert(Players.enroll(data,"host",context.character,context.catalog,{[context.character]=true}))
            data.events["1"]={id="smoke-open-stop"}; data.encounters["1"]={hasMob=false,resolved=true,rolled=true}
            assert(ui.transitionParty("scene.leaveTrain",{}).ok)
            assert(ui.transitionParty("scene.returnTrain",{}).ok)
            local before,write=data.resources.coal,love.filesystem.write
            love.filesystem.write=function(path,contents)
                if path==Save.path(99) then return false,"injected departure save failure" end
                return write(path,contents)
            end
            game.travelConfirm=true; context.draw(); control(ui.travelYes)
            assert(data.coop.journey and data.coop.journey.phase=="departed" and ui.checkpointStatus().pending)
            local paid=data.resources.coal; assert(paid<before)
            context.update(3); assert(data.location==1 and game.travelTransition.t==0)
            love.filesystem.write=write; control({x=190,y=438,w=185,h=58})
            assert(not ui.checkpointStatus().pending)
            local saved=assert(Save.read(99)); assert(saved.coop.journey.phase=="departed" and saved.resources.coal==paid)
            assert(context.enterGame(saved)); data=game.saveData
            assert(game.travelTransition and not game.travelTransition.changed and data.resources.coal==paid)
            for index=1,100 do
                if not data.coop.journey then break end
                context.update(.1)
            end
            assert(data.location==2 and not data.coop.journey and not game.travelTransition and data.resources.coal==paid)
            saved=assert(Save.read(99)); local host,guest=saved.players.host,saved.players.companion
            assert(saved.location==2 and not saved.coop.journey and saved.resources.coal==paid)
            assert((host.playerX-guest.playerX)^2+(host.playerY-guest.playerY)^2>=24^2)
            return {ok=true,twoSavedActors=true,distinctSpawns=true,paidOnce=true,reloadedDeparture=true,
                arrivalCheckpointed=true,input=context.mobileEnabled() and "production touch callbacks" or "production mouse callbacks"}
        end) end,check=function(_,_,_,result) return result and result.ok end},
        {name="critical_checkpoint_blocks_and_retries",action=function() return fixture(function(data)
            data.location=4; data.scene="stop"; game.scene="stop"; context.setupNPC()
            local npc=data.currentNPC
            data.conversations.assignments["4"]=nil; data.conversations.nextStop=999
            game.player.x,game.player.y=game.npcActor.x+30,game.npcActor.y
            data.resources.food=6; data.goodwill=0
            data.supplyQuests={{origin=1,destination=4,cargoKind="food",complete=false}}
            data.mailQuests={{origin=1,destination=4,recipient=npc,complete=false}}
            local function talk()
                game.dialogue=nil; game.questOffer=nil; ui.interaction={kind="npc"}
                love.keypressed("e"); love.keyreleased("e")
            end
            talk(); assert(data.supplyQuests[1].complete and not ui.checkpointStatus().pending)
            local write=love.filesystem.write
            love.filesystem.write=function(path,contents)
                if path==Save.path(99) then return false,"injected checkpoint failure" end
                return write(path,contents)
            end
            talk(); assert(data.mailQuests[1].complete and ui.checkpointStatus().pending)
            local revision,clock=data.coop.revision,game.animationClock
            context.update(.3); context.draw()
            assert(game.animationClock==clock and ui.checkpointBlocked,"world advanced during failed checkpoint")
            love.keypressed("y"); love.keypressed("f12"); love.keyreleased("f12")
            control({x=387,y=438,w=185,h=58}); assert(ui.optionsOpen)
            context.draw(); control(ui.musicUp); control(ui.optionsBack)
            assert(not ui.optionsOpen and not ui.escMenuOpen)
            control({x=190,y=438,w=185,h=58})
            assert(ui.checkpointStatus().pending and data.coop.revision==revision and data.goodwill==2)
            love.filesystem.write=write
            control({x=190,y=438,w=185,h=58})
            assert(not ui.checkpointStatus().pending and not ui.checkpointBlocked)
            local saved=assert(Save.read(99)); local receipts=saved.coop.checkpoints.receipts
            assert(saved.mailQuests[1].complete and saved.supplyQuests[1].complete and saved.goodwill==2)
            assert(#receipts==2 and receipts[2].response.durable and receipts[2].response.revision==revision)
            context.update(.1); assert(game.animationClock>clock)
            return {ok=true,pendingVisible=true,worldPaused=true,settingsAvailable=true,retrySaved=true,rewardsOnce=true,
                input=context.mobileEnabled() and "production touch callbacks" or "production mouse callbacks"}
        end) end,check=function(_,_,_,result) return result and result.ok end},
        {name="device_preferences_campaign_isolation",action=function() return fixture(function(data)
            assert(data.coop.preferencesDetached and not data.accessibility and not data.audio.sfxVolume)
            local station,revision=data.audio.station,data.coop.revision
            local volume=Preferences.audio(data).musicVolume
            ui.optionsOpen=true; game.optionsPage="audio"; context.draw()
            control(ui.optionsStationVibes); control(ui.musicUp)
            assert(Preferences.audio(data).station=="vibes" and Preferences.hasOverride(data))
            assert(data.audio.station==station and data.coop.revision==revision,"Options mutated campaign radio")
            assert(Preferences.audio(data).musicVolume==math.min(1,volume+.05))
            context.draw(); control(ui.optionsFollowRadio)
            assert(not Preferences.hasOverride(data) and Preferences.audio(data).station==station)
            game.optionsPage="accessibility"; context.draw()
            local before=Accessibility.ensure(data).highContrast
            control(ui.accessHighContrast); assert(Accessibility.ensure(data).highContrast~=before and not data.accessibility)
            ui.optionsOpen=false; love.focus(false); love.focus(true)
            local restored=assert(Save.read(99))
            assert(restored.coop.preferencesDetached and not restored.accessibility and not restored.audio.musicVolume)
            local localStore=Preferences.new(love.filesystem)
            assert(localStore.values.accessibility.highContrast~=before and localStore.values.audio.musicVolume==math.min(1,volume+.05))
            return {ok=true,localAudio=true,localAccessibility=true,sharedRadioUnchanged=true,followRadio=true,
                savedSeparately=true,input=context.mobileEnabled() and "production touch callbacks" or "production mouse callbacks"}
        end) end,check=function(_,_,_,result) return result and result.ok end},
        {name="accepted_quest_authority_rewards",action=function() return fixture(function(data)
            data.location=4; data.scene="stop"; game.scene="stop"; context.setupNPC()
            local layout=context.ensureStopLayout(); local npc=data.currentNPC
            data.conversations.assignments["4"]=nil; data.conversations.nextStop=999
            game.player.x,game.player.y=game.npcActor.x+30,game.npcActor.y
            for index=1,data.inventoryCapacity do Items.write(data,nil,{kind="inventory",index=index},nil) end
            data.goodwill=0; data.helpHistory={}
            data.supplyQuests={{origin=1,destination=4,cargoKind="food",complete=false}}
            data.mailQuests={{origin=1,destination=4,recipient=npc,complete=false}}
            data.resources.food=6
            local function talk()
                game.dialogue=nil; game.questOffer=nil; ui.interaction={kind="npc"}
                love.keypressed("e"); love.keyreleased("e"); context.draw()
            end
            talk()
            assert(data.supplyQuests[1].complete and data.supplyQuests[1].rewardRecipients.host,"supply delivery bypassed authority")
            assert(data.resources.food==3 and data.goodwill==1)
            talk(); assert(data.mailQuests[1].complete and data.mailQuests[1].rewardRecipients.host and data.goodwill==2)
            layout.npcOffers[npc]="item"
            local request=Help.ensureRequest(layout,npc,"item",4,data)
            request.accepted=true; Quests.accept(data,request.sessionId)
            Items.write(data,nil,{kind="inventory",index=1},request.item)
            talk(); assert(request.complete and data.inventory[1]==nil and data.goodwill==4,
                "item help: complete="..tostring(request.complete).." item="..tostring(data.inventory[1])
                .." goodwill="..tostring(data.goodwill).." dialogue="..tostring(game.dialogue and game.dialogue.text))
            love.focus(false); love.focus(true)
            local restored=assert(Save.read(99))
            assert(restored.supplyQuests[1].complete and restored.mailQuests[1].rewardRecipients.host
                and restored.helpQuestSessions[request.sessionId].rewardClaimed and restored.coop.randomState)
            return {ok=true,supplies=true,mail=true,itemHelp=true,rewardOnce=true,persisted=true,input="production keyboard interaction"}
        end) end,check=function(_,_,_,result) return result and result.ok end},
        {name="train_object_authority_controls",action=function() return fixture(function(data)
            data.scene="train"; game.scene="train"; data.stopped=true
            local item={name="potted-sprout",scene="train",carIndex=1,x=790,y=600,scale=1}
            data.droppedItems[#data.droppedItems+1]=item; Entities.ensure(data)
            game.editMode=true; context.draw()
            handle(item)
            assert(ui.editedDecoration()==item,"object handle did not acquire its lease: "..tostring(ui.decorationMessage))
            local x=item.x
            context.draw(); control(ui.editRight); assert(item.x==x+5,"editor movement did not commit")
            context.draw(); control(ui.editLarger); assert(math.abs(item.scale-1.1)<.001)
            context.draw(); control(ui.editRotate); assert(math.abs(item.rotation-math.pi/4)<.001)
            context.draw(); control(ui.editHue); assert(item.hue and item.hue>0)
            love.focus(false); love.focus(true)
            assert(not ui.editedDecoration(),"focus loss retained the decoration lease")
            context.draw(); handle(item); assert(ui.editedDecoration()==item)
            context.draw(); control(ui.editPickup); assert(not Entities.find(data,item.entityId),"editor collection failed")
            game.editMode=false
            local radio
            for _,candidate in ipairs(data.droppedItems) do if candidate.name=="boombox-radio" and candidate.scene=="train" then radio=candidate; break end end
            assert(radio); game.player.x,game.player.y=radio.x,radio.y
            ui.nearRadio=true; data.audio.station="chill"; game.dialogue=nil
            love.keypressed("p"); love.keyreleased("p"); context.draw()
            assert(ui.radioOpen); control(ui.radioVibes,true)
            assert(data.audio.station=="vibes" and (data.coop.revisions.radio or 0)>0,"radio input bypassed authority")
            love.focus(false); love.focus(true)
            local restored=assert(Save.read(99)); assert(restored.audio.station=="vibes" and not Entities.find(restored,item.entityId))
            return {ok=true,moved=true,scaled=true,rotated=true,tinted=true,collected=true,focusReleased=true,radio=true,
                input=context.mobileEnabled() and "production touch callbacks" or "production mouse callbacks"}
        end) end,check=function(_,_,_,result) return result and result.ok end},
    }
end
return Smoke
