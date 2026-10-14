-- One connected adventure from a resolved Stop 6 arrival checkpoint. The only
-- seed is the initial campaign. Navigation, cache, combat, trade, storage and
-- saved-slot hosting subsequently use production inputs and real time.
local Helpers={}
-- Ordinary production commands replenish at two per second. Wait slightly
-- longer between actual control actions rather than consuming the burst budget.
Helpers.ACTION_INTERVAL=.6
function Helpers.actionReady(now,last) return now-last>=Helpers.ACTION_INTERVAL end
function Helpers.driveTouch(controls,held,press,move,release,point,dx,dy)
    local id='adventure-walk';local owned=controls.touches[id]
    local trace={heldBefore=held,ownerBefore=owned and owned.kind,movementActive=controls:isMovementActive(),
        gameplayActive=controls:isGameplayActive(),recovered=false}
    local stick=controls.joystick
    if held and (not owned or owned.kind~='joystick' or controls.joystickTouch~=id) then
        local x,y=point(stick.x,stick.y);trace.releaseResult=release(id,x,y);held=false;trace.recovered=true
    end
    if not trace.movementActive then
        if held then local x,y=point(stick.x,stick.y);release(id,x,y);held=false end
        return held,trace
    end
    if not held then
        trace.pressLogicalX,trace.pressLogicalY=stick.x,stick.y
        local x,y=point(stick.x,stick.y);trace.pressX,trace.pressY=x,y
        trace.pressResult=press(id,x,y)
        owned=controls.touches[id];held=owned and owned.kind=='joystick' and controls.joystickTouch==id or false
    end
    if held then
        trace.moveLogicalX,trace.moveLogicalY=stick.x+dx*stick.radius*.95,stick.y+dy*stick.radius*.95
        local x,y=point(trace.moveLogicalX,trace.moveLogicalY);trace.moveX,trace.moveY=x,y
        trace.moveResult=move(id,x,y,0,0)
    end
    return held,trace
end
function Helpers.copy(value)
    if type(value)~='table' then return value end
    local result={}; for k,v in pairs(value) do result[k]=Helpers.copy(v) end; return result
end
function Helpers.record(value)
    if type(value)~='table' then return value end
    local result={}; for key,entry in pairs(value) do result[tostring(key)]=Helpers.record(entry) end; return result
end
function Helpers.same(a,b,roundTrip)
    if type(a)~=type(b) then return false end
    if type(a)=='table' then
        for key,value in pairs(a) do if not Helpers.same(value,b[key],roundTrip) then return false end end
        for key in pairs(b) do if a[key]==nil then return false end end; return true
    end
    return a==b or roundTrip and type(a)=='number' and (a~=math.floor(a) or b~=math.floor(b))
        and math.abs(a-b)<=1e-11*math.max(1,math.abs(a),math.abs(b))
end
function Helpers.segment(x,y,tx,ty,walkable)
    local n=math.max(1,math.ceil(math.sqrt((tx-x)^2+(ty-y)^2)/4))
    for i=1,n do if not walkable(x+(tx-x)*i/n,y+(ty-y)*i/n) then return false end end
    return true
end
-- A bounded read-only pilot graph follows actual settlement collision masks.
-- This chooses input direction; it never moves either actor itself.
function Helpers.route(x,y,tx,ty,walkable,width,height)
    if Helpers.segment(x,y,tx,ty,walkable) then return tx,ty end
    width,height=width or 960,height or 720
    local step=12; local queue,seen,head={},{},1
    local function add(q,r,parent)
        local px,py=q*step,r*step; local key=q..':'..r
        if seen[key] or px<6 or px>width-6 or py<6 or py>height-6 or not walkable(px,py) then return end
        local node={x=px,y=py,q=q,r=r,parent=parent}; seen[key]=node; queue[#queue+1]=node
    end
    local q,r=math.floor(x/step+.5),math.floor(y/step+.5)
    for dq=-2,2 do for dr=-2,2 do
        if Helpers.segment(x,y,(q+dq)*step,(r+dr)*step,walkable) then add(q+dq,r+dr) end
    end end
    local goal,best,bestDistance
    while queue[head] do
        local node=queue[head]; head=head+1
        local d=(node.x-tx)^2+(node.y-ty)^2
        if not bestDistance or d<bestDistance then best,bestDistance=node,d end
        if d<=24^2 and Helpers.segment(node.x,node.y,tx,ty,walkable) then goal=node; break end
        for _,dir in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
            local nx,ny=(node.q+dir[1])*step,(node.r+dir[2])*step
            if Helpers.segment(node.x,node.y,nx,ny,walkable) then add(node.q+dir[1],node.r+dir[2],node) end
        end
    end
    goal=goal or bestDistance and bestDistance<=36^2 and best
    if not goal then return nil end
    while goal.parent do goal=goal.parent end
    return goal.x,goal.y
end
function Helpers.guestAreaWaypoint(data,areaId,x,y,tx,ty,areas)
    local area=areas.definition(areaId); if not area then return nil end
    return Helpers.route(x,y,tx,ty,function(px,py) return areas.isWalkable(data,areaId,px,py,true) end,area.width,area.height)
end
function Helpers.readyReceipt(reply,id,revision)
    return reply and reply.requestId==id and reply.ok==true and reply.durable==true and revision>=reply.revision
end
function Helpers.newSession(network,oldSession,expected)
    return network and network.status=='ready' and network.sessionId~=oldSession and network.sessionId==expected
end
function Helpers.reliableView(lp)
    local view=lp.clientView; local replica=lp.replica and lp.replica.data
    local runtime=view and view.runtime; local data=runtime and runtime.saveData
    return lp.network and lp.network.status=='ready' and view and view.ready and replica and data
        and replica.coop.sceneEpoch==view.epoch and data.coop.sceneEpoch==view.epoch
        and runtime.scene==data.scene and runtime.scene==replica.scene
        and data.location==replica.location and data.activeExpeditionArea==replica.activeExpeditionArea
end
function Helpers.motionReady(lp)
    local view,frame=lp.clientView,lp.motionFrame
    return Helpers.reliableView(lp) and frame and frame.ready and not frame.paused
        and type(view.motionId)=='number' and type(view.lastSerial)=='number'
        and frame.sessionId==lp.network.sessionId and frame.sceneEpoch==view.epoch
        and frame.motionId==view.motionId and frame.serial==view.lastSerial and frame.domain==view.modalDomain
end
function Helpers.guestArrival(lp,x,y,radius,areas)
    if not Helpers.motionReady(lp) then return false end
    local view=lp.clientView;local data=view.runtime.saveData;local predicted=view.runtime.player
    local checked=require('game.net.movement').unpackActor(lp.motionFrame.companion)
    if (checked.x-x)^2+(checked.y-y)^2>radius^2 or (predicted.x-x)^2+(predicted.y-y)^2>radius^2 then return false end
    return data.scene~='expedition' or areas.canReach(data,data.activeExpeditionArea,checked.x,checked.y,x,y,true)
end
function Helpers.reachTrace(data,actor,x,y,radius,areas)
    if not actor then return 'unknown' end
    local distance=math.sqrt((actor.x-x)^2+(actor.y-y)^2)
    local reachable=data.scene~='expedition' or areas.canReach(data,data.activeExpeditionArea,actor.x,actor.y,x,y,true)
    return string.format('%.3f,%.3f distance=%.3f radius=%s canReach=%s',actor.x,actor.y,distance,tostring(radius),tostring(reachable))
end
function Helpers.touchInteraction(role,scene,controls)
    return role=='host' and scene=='expedition' and controls.secondary or controls.primary
end
function Helpers.identities(items)
    local result={}; for _,item in pairs(items or {}) do result[item.id]=item.name end; return result
end
function Helpers.purchasedIdentity(before,items,details)
    if not details or details.delivery~='inventory' then return nil end
    local after=Helpers.identities(items); local count,new=0,nil
    for id,name in pairs(before) do if after[id]~=name then return nil end end
    for _,item in pairs(items or {}) do
        if not before[item.id] then count=count+1; new=item end
    end
    return count==1 and new.name==details.item and new.id or nil
end
function Helpers.purchasedSlot(beforeNames,beforeIds,names,items,details,isGear)
    if not details or details.delivery~='inventory' then return nil end
    for index,name in pairs(beforeNames) do if names[index]~=name then return nil end end
    local index,count=nil,0
    for slot,name in pairs(names) do if beforeNames[slot]==nil then index=slot;count=count+1 end end
    if count~=1 or names[index]~=details.item then return nil end
    if isGear(details.item) then
        local id=Helpers.purchasedIdentity(beforeIds,items,details); if not id then return nil end
        return index,id
    end
    if not Helpers.same(beforeIds,Helpers.identities(items),false) then return nil end
    return index,false
end
function Helpers.captureReady(request,done) return not request and not done end
function Helpers.ordinaryOffer(data,state)
    local q=data and data.lastStand; local life=q and q.lifecycle
    return life and life.mode=='offer' and state and state.mode=='offer' and state.capture==true
        and state.quest==q and not state.pendingProgression and not state.paused and life.entityId..':'..life.revision or nil
end
function Helpers.townReady(data,runtime,declinedKey)
    local q=data and data.lastStand;local life=q and q.lifecycle;local state=runtime and runtime.lastStand
    return data and runtime and data.scene=='stop' and runtime.scene=='stop' and runtime.state=='game'
        and q and q.state=='declined' and q.declinedStop==data.location and life and life.mode=='approach'
        and declinedKey==life.entityId..':'..(life.revision-1)
        and not (state and (state.capture or state.pendingProgression)) or false
end
function Helpers.progress(previous,stage,x,y,now)
    if not previous or previous.stage~=stage or (previous.x-x)^2+(previous.y-y)^2>9 then
        return {stage=stage,x=x,y=y,at=now},0
    end
    return previous,now-previous.at
end
if rawget(_G,'ADVENTURE_FIXTURE_HELPERS') then return Helpers end

io.stdout:setvbuf('no')
local role=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'))
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local restart=os.getenv('MOUSE_FRONTIER_ADVENTURE_HOST_RESTART')=='1'
local resumed=os.getenv('MOUSE_FRONTIER_ADVENTURE_RESUMED')=='1'
local Save=require('game.save'); local Schema=require('game.save_schema'); local Codec=require('game.net.codec'); local Players=require('game.coop_players')
local Areas=require('game.expedition_areas'); local Stops=require('game.stops'); local Random=require('game.coop_random')
local Settlements=require('game.settlements'); local Inventory=require('game.inventory'); local Items=require('game.item_instances')
local Rules=require('game.battle_rules'); local Weapons=require('game.battle_weapon_ownership')
local Actors=require('game.battle_actors'); local Grid=require('game.battle_grid'); local Trade=require('game.merchant_trade')
local Style=require('game.ui_layout'); local Viewport=require('game.viewport'); local WorldView=require('game.world_view')
local WorldPause=require('game.world_pause')
local app,c,stage,started,finished,oldKeyboard,capture,capturePending,afterCapture
local movement,joystickHeld={},false; local lastAction=0; local lastReport=0; local navigation
local request,requestCommand,requestAfter,requestVerify; local battleIntent,battleId; local battles,hostAttacks=0,0
local guestAttacks=0; local oldSession; local restartRequested=false; local storedId,storedRecord,storedAmmo
local supplies={}; local purchasedName
local chestId,purchasedId,baselineFood,baselineHostWeapon,baselineGuestWeapon,initialCampaign,initialCompanion
local captures={}; local checkpoint; local tradeIndex; local gotCache=false; local consumed=false; local cachedItems=0
local progress,stallLogged,stallFailure,injectedKeyboard,offerDecision,touchTrace,touchLastPress,townWaitStarted
local function check(value,message) assert(value,message) end
local function file(name,value)
    local stream=io.open(root..'/'..name,value~=nil and 'wb' or 'rb'); if not stream then return nil end
    local result=value~=nil and stream:write(tostring(value)) or stream:read('*a'); stream:close(); return result
end
local function button(key) local result=app.keypressed(key);app.keyreleased(key);return result end
local function coords(x,y) local ox,oy,sx,sy=Viewport.transform(960,720); return ox+x*sx,oy+y*sy end
local function press(rect)
    check(rect,'missing production control at '..tostring(stage)); check(rect.enabled~=false,'disabled production control at '..tostring(stage))
    local x,y=coords(rect.x+rect.w/2,rect.y+rect.h/2)
    local result
    if touch then result=app.touchpressed('adventure-control',x,y); app.touchreleased('adventure-control',x,y)
    else result=app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
    lastAction=love.timer.getTime()
    return result
end
local function menu() if not c.ui.localPlay.menuOpen then button('f8') end end
local function click(id,text) app.draw(); press(c.ui.localPlayControls[id]); if text then app.textinput(text); button('return') end end
local function back() if c.ui.localPlay.menuOpen then click('close') end end
local function stopWalk()
    movement={}; navigation=nil
    if joystickHeld then app.touchreleased('adventure-walk',0,0); joystickHeld=false end
end
local function photo(name,fn)
    stopWalk(); check(not capture and not capturePending,'overlapping screenshot requests')
    capture=name; afterCapture=fn
end
local function data() return role=='host' and c.runtime.saveData or c.ui.localPlay.clientView.runtime.saveData end
local function runtime() return role=='host' and c.runtime or c.ui.localPlay.clientView.runtime end
local function ready()
    local lp=c.ui.localPlay
    return Helpers.motionReady(lp) and lp.clientView:actionsAllowed()
end
local function ownItem(name)
    local d=data(); for i,value in pairs(d.inventory or {}) do if value==name then return i,d.itemSlots.inventory[i] end end
end
local function ownIdentity(id)
    local d=data(); for index,item in pairs(d.itemSlots.inventory or {}) do if item.id==id then return index,item end end
end
local function travelChest(d)
    for _,item in ipairs(d.droppedItems) do if item.name=='travel-chest' and item.scene=='train' and item.carIndex==1 then return item end end
    error('original travel chest missing')
end
local function actualUses(actor)
    local uses=0; for _,count in pairs(actor.weaponProficiency or {}) do uses=uses+count end; return uses
end
local signatureLimits={maxBytes=131072,maxDepth=20,maxEntries=8192,maxStringBytes=512}
local function publicSignature(d)
    local h,g=d.players.host,d.players.companion; local cache=d.expeditions[Areas.SURFACE_ID].chests['surface-cache']
    return assert(Codec.encode(Helpers.record({scene=d.scene,location=d.location,epoch=d.coop.sceneEpoch,resources=d.resources,
        scrap=d.scrap,goodwill=d.goodwill,host={inventoryNames=h.inventory,equipment=h.itemSlots.equipment,ammo=h.ammo,health=h.health,stats=h.stats,proficiency=h.weaponProficiency},
        guest={inventoryNames=g.inventory,inventory=g.itemSlots.inventory,equipment=g.itemSlots.equipment,ammo=g.ammo,health=g.health,stats=g.stats,proficiency=g.weaponProficiency},
        chest=travelChest(d),cache=cache,mobs=d.expeditions[Areas.SURFACE_ID].mobs,layout=d.stopLayouts['6'],
        trade=d.relationships,tactical=d.tacticalBattle,pressure=d.roamingEncounter}),signatureLimits))
end
local function samePublic(d,expected,label,roundTrip)
    check(Helpers.same(assert(Codec.decode(publicSignature(d),signatureLimits)),assert(Codec.decode(expected,signatureLimits)),roundTrip),label)
end
local function signature(d)
    return assert(Codec.encode({campaign=d.coop.network.campaignId,companion=d.coop.network.companionId,
        rng=d.coop.randomState,public=publicSignature(d)}, {maxBytes=262144,maxDepth=20,maxEntries=8192,maxStringBytes=131072}))
end
local function sameSignature(d,expected,label,roundTrip)
    local limits={maxBytes=262144,maxDepth=20,maxEntries=8192,maxStringBytes=131072}
    local have=assert(Codec.decode(signature(d),limits)); local want=assert(Codec.decode(expected,limits))
    samePublic(d,want.public,label..' (public facts)',roundTrip); have.public=nil; want.public=nil
    check(Helpers.same(have,want,false),label..' (private identity/RNG)')
end
local function hostControl(name)
    app.draw()
    if not c.ui[name] and touch then
        local controls=c.getMobileControls()
        press(Style.transformRectFor('mobileControls',controls:uiBounds(),controls.menu)); app.draw()
    end
    local rect=c.ui[name];check(rect,'missing actual host control '..name)
    local px,py=coords(rect.x+rect.w/2,rect.y+rect.h/2)
    print('LAN_ADVENTURE_HOST_CONTROL name='..name..' logical='..rect.x..','..rect.y..','..rect.w..','..rect.h
        ..' physical='..px..','..py..' state='..c.runtime.state..' runtimeScene='..c.runtime.scene..' campaignScene='..c.runtime.saveData.scene
        ..' dialogue='..tostring(c.runtime.dialogue~=nil)..' inventory='..tostring(c.runtime.inventoryOpen)..' trade='..tostring(c.runtime.tradeOpen)
        ..' pose='..tostring(c.runtime.poseMenu)..' radio='..tostring(c.ui.radioOpen)..' checkpoint='..tostring(c.session.checkpointPending))
    local result=press(rect)
    print('LAN_ADVENTURE_HOST_CONTROL_RESULT name='..name..' callback='..tostring(result)..' state='..c.runtime.state
        ..' runtimeScene='..c.runtime.scene..' campaignScene='..c.runtime.saveData.scene..' checkpoint='..tostring(c.session.checkpointPending))
end
local function hostSavedEntry()
    local lp=c.ui.localPlay; lp.port=port; c.runtime.state='slots'; menu(); click('host')
    check(lp.hostingIntent=='selecting' and not lp.menuOpen,'Host Saved Journey did not open real slot selection')
    app.draw(); press(c.ui.slots[1]); check(lp.network and c.session.networkMode=='host','real saved slot failed to host '..tostring(lp.error)); back()
end
local function generatedInitial()
    local draft=c.newSave(c.characters[1]); draft.location=6; draft.stopped=true
    draft.encounters['6']={rolled=true,hasMob=false,resolved=true}; draft.events['6']={id='resolved'}
    for seed=1,4096 do
        local candidate=Players.attachHost(Helpers.copy(draft)); candidate.coop.randomState=nil
        local layout=Stops.ensure(candidate,c.catalog,'stop',Random.generator(candidate,seed))
        if layout.npcOutside=='crow-merchant.png' then
            check(layout.npcOffers[layout.npcOutside]=='trade' and next(layout.tradeStock),'natural crow merchant failed')
            -- Normal scene transitions prepare identity after generating their
            -- NPC/stock. This detached initial checkpoint follows that same
            -- path; existing records are validated and are never replaced.
            local entities,entityReason=require('game.coop_entities').ensure(candidate)
            check(entities,'generated initial entities invalid: '..tostring(entityReason))
            local items,itemReason=Items.ensure(candidate)
            check(items,'generated initial owned items invalid: '..tostring(itemReason))
            local valid,reason=Schema.validate(candidate)
            check(valid,'generated initial Schema.validate rejected: '..tostring(reason))
            print('LAN_ADVENTURE_SEED production=true seed='..seed..' merchant='..layout.npcOutside)
            return candidate
        end
    end
    error('bounded production seed search did not yield a Stop 6 crow merchant')
end
local function load()
    started=love.timer.getTime(); stage='load'; love.math.setRandomSeed(13102026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    oldKeyboard=love.keyboard.isDown
    love.keyboard.isDown=function(...)
        for i=1,select('#',...) do if movement[select(i,...)] then return true end end
        return oldKeyboard(...)
    end
    injectedKeyboard=love.keyboard.isDown
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    if role=='host' then
        local transition=c.ui.transitionParty
        check(type(transition)=='function','production party transition callback absent')
        c.ui.transitionParty=function(name,args)
            local reply=transition(name,args)
            print('LAN_ADVENTURE_PARTY_COMMAND command='..name..' ok='..tostring(reply and reply.ok)..' reason='..tostring(reply and reply.reason)
                ..' durable='..tostring(reply and reply.durable)..' checkpoint='..tostring(c.session.checkpointPending)
                ..' state='..c.runtime.state..' runtimeScene='..c.runtime.scene..' campaignScene='..tostring(c.runtime.saveData and c.runtime.saveData.scene))
            return reply
        end
        if not resumed then
            Save.remove(1); c.runtime.selectedSlot=1
            local entered,entryReason=c.enterGame(generatedInitial())
            check(entered,'initial resolved-arrival checkpoint invalid: '..tostring(entryReason))
            check(Save.write(1,c.runtime.saveData),'initial checkpoint write failed')
            c.runtime.saveData=nil; c.runtime.selectedSlot=nil
        else
            sameSignature(assert(Save.read(1)),file('resume.expected'),'fresh-process disk checkpoint changed',false)
        end
        hostSavedEntry()
        local execute=lp.authority.execute
        lp.authority.execute=function(authority,id,generation,request)
            local watched=request.command=='expedition.cache'
            if watched then
                local actual=c.runtime.saveData;local definition=Areas.current(actual);local spot
                local _,record=require('game.coop_entities').find(actual,request.args.containerId)
                for _,entry in ipairs(definition and definition.interactions or {})do
                    if entry.kind=='chest' and record and entry.chestId==record.key then spot=entry end
                end
                if spot then
                    print('LAN_ADVENTURE_CACHE_AUTHORITY request='..request.requestId..' sceneEpoch='..actual.coop.sceneEpoch
                        ..' motionId='..tostring(lp.motion and lp.motion.motionId)..' actor='
                        ..Helpers.reachTrace(actual,lp.motion and lp.motion.actor,spot.x,spot.y,spot.radius,Areas))
                end
            end
            local reply=execute(authority,id,generation,request)
            if watched then print('LAN_ADVENTURE_CACHE_REPLY request='..request.requestId..' ok='..tostring(reply.ok)..' reason='..tostring(reply.reason))end
            return reply
        end
        if resumed then
            sameSignature(c.runtime.saveData,file('resume.expected'),'saved-slot entry changed adventure state',false)
            check(lp.authority.sessionId~=file('resume.session'),'new process reused host session')
            file('host.resumed.session',lp.authority.sessionId); storedId=file('stored.id'); stage='resumed'
        else stage='hosting' end
        print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil; menu(); click('address','127.0.0.1:'..port)
        click('name','Adventure friend'); click('next'); click('join'); stage='joining'
    end
end
local function walkTo(x,y,radius)
    local r=runtime(); local d=data(); local px,py=r.player.x,r.player.y
    local arrived=role=='guest' and Helpers.guestArrival(c.ui.localPlay,x,y,radius,Areas)
        or role=='host' and (px-x)^2+(py-y)^2<=radius^2
    if arrived then stopWalk(); return true end
    local now=love.timer.getTime(); local nx,ny
    if d.scene=='expedition' then
        if role=='guest' then
            if not navigation or navigation.areaId~=d.activeExpeditionArea or navigation.epoch~=d.coop.sceneEpoch
                or navigation.x~=x or navigation.y~=y or now-navigation.at>.4 or (px-navigation.nx)^2+(py-navigation.ny)^2<8^2 then
                nx,ny=Helpers.guestAreaWaypoint(d,d.activeExpeditionArea,px,py,x,y,Areas)
                navigation={x=x,y=y,nx=nx,ny=ny,at=now,areaId=d.activeExpeditionArea,epoch=d.coop.sceneEpoch}
            else nx,ny=navigation.nx,navigation.ny end
        else
            nx,ny=Areas.pathTarget(d,d.activeExpeditionArea,px,py,x,y)
            navigation={x=x,y=y,nx=nx,ny=ny,at=now,areaId=d.activeExpeditionArea,epoch=d.coop.sceneEpoch}
        end
    elseif d.scene=='stop' then
        if not navigation or navigation.x~=x or navigation.y~=y or now-navigation.at>.4 or (px-navigation.nx)^2+(py-navigation.ny)^2<8^2 then
            nx,ny=Helpers.route(px,py,x,y,function(ax,ay) return Settlements.isWalkable(6,ax,ay) end)
            navigation={x=x,y=y,nx=nx,ny=ny,at=now}
        else nx,ny=navigation.nx,navigation.ny end
    else nx,ny=x,y;navigation={x=x,y=y,nx=nx,ny=ny,at=now} end
    check(nx and ny,'no authored input route '..d.scene..' from '..px..','..py..' to '..x..','..y)
    local dx,dy=nx-px,ny-py; local length=math.max(1,math.sqrt(dx*dx+dy*dy)); dx,dy=dx/length,dy/length
    if touch then
        app.draw(); local controls=role=='guest' and c.ui.localPlay.clientView.mobile or c.getMobileControls()
        local stick=controls.joystick; check(stick,'production movement joystick missing')
        local function point(ax,ay)
            if role=='host' then local p=Style.transformRectFor('mobileControls',controls:uiBounds(),{x=ax,y=ay,w=0,h=0}); ax,ay=p.x,p.y end
            return coords(ax,ay)
        end
        joystickHeld,touchTrace=Helpers.driveTouch(controls,joystickHeld,app.touchpressed,app.touchmoved,app.touchreleased,point,dx,dy)
        if touchTrace.pressX then touchLastPress=Helpers.copy(touchTrace) end
        if touchTrace.recovered then print('LAN_ADVENTURE_TOUCH_REPRESS stage='..stage..' movementActive='..tostring(touchTrace.movementActive)
            ..' ownerBefore='..tostring(touchTrace.ownerBefore)..' pressResult='..tostring(touchTrace.pressResult)) end
    else movement={}; if math.abs(dx)>.16 then movement[dx>0 and 'd' or 'a']=true end; if math.abs(dy)>.16 then movement[dy>0 and 's' or 'w']=true end end
    return false
end
local function interact()
    stopWalk(); app.draw()
    if touch then
        local controls=role=='guest' and c.ui.localPlay.clientView.mobile or c.getMobileControls()
        local point=Helpers.touchInteraction(role,runtime().scene,controls); local rect={x=point.x,y=point.y,w=0,h=0}
        if role=='host' then rect=Style.transformRectFor('mobileControls',controls:uiBounds(),rect) end
        return press(rect)
    else local result=button('e'); lastAction=love.timer.getTime();return result end
end
local function bagPress(rect) press(Style.transformRectFor('inventory',{x=25,y=35,w=910,h=660},rect)) end
local function inventorySlot(index) return touch and Inventory.mobileInventorySlotRect(index) or Inventory.inventorySlotRect(index) end
local function awaitRequest(panel,nextStage,verify)
    check(panel.pending,'actual guest input did not emit command at '..stage)
    request=panel.pending.id; requestCommand=panel.pending.command; requestAfter=nextStage; requestVerify=verify
end
local function completeRequest(lp)
    if not request then return false end
    local reply=lp.network and lp.network.lastCommandResult
    if not reply or reply.requestId~=request then return true end
    if reply.savePending or reply.reason=='save_pending' or reply.reason=='busy' then return true end
    check(reply.ok,'adventure command rejected: '..tostring(requestCommand)..' '..tostring(reply.reason))
    if not Helpers.readyReceipt(reply,request,data().coop.revision) then return true end
    local v=lp.clientView
    if v.inventory.pending or v.trade.pending or v.expedition.pending or v.battles.pending then return true end
    if requestVerify then requestVerify(reply) end
    stage=requestAfter; request=nil; requestAfter=nil; requestVerify=nil; lastAction=love.timer.getTime()
    return true
end
local function cell(q,r)
    local x,y=Grid.boardToScreen(1,q,r)
    if role=='guest' then x,y=c.ui.localPlay.clientView.battles.worldView.toScreen(x,y) else x,y=WorldView.toScreen(x,y) end
    press(Style.transformRectFor('battle',{x=0,y=0,w=960,h=720},{x=x,y=y,w=0,h=0}))
end
local function battlePilot()
    local r=runtime(); local d=data(); local b=r.battle; if not b then battleIntent=nil; return false end
    stopWalk(); local id=d.tacticalBattle.encounterId
    if battleId~=id then battleId=id; battles=battles+1; battleIntent=nil; photo(role..'-battle-'..battles..'.png'); return true end
    if b.finished then
        check(b.finished=='win','natural adventure combat lost')
        if role=='guest' and not file('guest.victory.'..id) then photo('guest-victory-'..battles..'.png',function() file('guest.victory.'..id,'true') end)
        elseif role=='host' and file('guest.victory.'..id) then
            app.draw(); press(c.ui.battleContinue); check(not c.runtime.saveData.tacticalBattle,'host Continue failed'); file('battle.completed','true')
            if stage=='seek-battle' then stage='return-town' end
        end
        return true
    end
    if b.intro or (b.attackTimer or 0)>0 or b.projectile then return true end
    for _,u in ipairs(b.units) do if u.moveAnim or (u.actionTimer or 0)>0 or (u.hitTimer or 0)>0 then return true end end
    local active=Rules.activeUnit(b); if not active or Actors.id(active)~=role and not (role=='guest' and Actors.id(active)=='companion') then return true end
    if role=='guest' and (not c.ui.localPlay.clientView.battles:canAct(active) or c.ui.localPlay.clientView.battles.pending) then return true end
    if role=='host' and c.ui.localPlay.authority.pendingSave then return true end
    if love.timer.getTime()-lastAction<.18 then return true end
    app.draw(); local ui=role=='host' and c.ui or c.ui.localPlay.clientView.ui
    if b.phase=='target' then
        local info=Weapons.resolve(d,active,b.chosenItemId or b.chosenWeapon,c.catalog)
        if info then for _,enemy in ipairs(b.units) do
            if enemy.team=='enemy' and enemy.hp>0 and Rules.distance(active,enemy)<=Rules.weaponRange(c.catalog,info.name)
                and (c.catalog.weaponCombat[info.name].kind~='ranged' or Rules.lineOfSight(b,active,enemy)) then
                cell(enemy.q,enemy.r); if role=='host' then hostAttacks=hostAttacks+1 else guestAttacks=guestAttacks+1; file('guest.attacks',guestAttacks) end
                return true
            end
        end end
        error('selected weapon has no legal natural target')
    end
    local best,enemy,damage
    for index,selector in ipairs(Weapons.options(d,active,c.catalog)) do
        local info=Weapons.resolve(d,active,selector,c.catalog); local combat=info and c.catalog.weaponCombat[info.name]
        local actor=Actors.data(d,active)
        if info and info.durability>0 and (not combat.ammo or (actor.ammo[combat.ammo] or 0)>0) then
            for _,target in ipairs(b.units) do if target.team=='enemy' and target.hp>0
                and Rules.distance(active,target)<=Rules.weaponRange(c.catalog,info.name)
                and (combat.kind~='ranged' or Rules.lineOfSight(b,active,target)) then
                local power=c.catalog.weaponStats[info.name].max
                if not damage or power>damage then best,enemy,damage=index,target,power end
            end end
        end
    end
    if best then press(ui.battleWeapons[best]); return true end
    if not b.moveUsed and b.phase~='action' then
        local nearest; for _,target in ipairs(b.units) do if target.team=='enemy' and target.hp>0 and (not nearest or Rules.distance(active,target)<Rules.distance(active,nearest)) then nearest=target end end
        local move=nearest and Rules.bestAdvance(b,active,nearest,active.move,1)
        if move and (move.q~=active.q or move.r~=active.r) then press(ui.battleMove); cell(move.q,move.r); return true end
    end
    press(ui.battleEnd); return true
end
local function finish()
    if finished then return end; finished=true; stopWalk(); if oldKeyboard then love.keyboard.isDown=oldKeyboard end
    check(app.quit()~=true,'adventure quit cancelled')
    print('LAN_SMOKE_OK role='..role..' adventure=true naturalNavigation=true normalStarterGear=true naturalCombat=true actualRewards=true'
        ..' ownedCache=true trade=true storage=true diskResume='..tostring(restart)..' input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function hostOfferPilot(lp)
    local d,r=c.runtime.saveData,c.runtime
    if offerDecision and offerDecision.sent then
        stopWalk()
        if c.session.checkpointPending or lp.authority.pendingSave or r.lastStand and r.lastStand.pendingProgression then return true end
        local q=d.lastStand;local disk=assert(Save.read(1),'declined offer checkpoint missing')
        check(q.lifecycle.entityId==offerDecision.id and q.lifecycle.revision==offerDecision.revision+1
            and q.lifecycle.mode=='approach' and q.state=='declined' and q.declinedStop==d.location,'host Not Now did not decline the actual offer')
        check(Helpers.same(disk.lastStand.lifecycle,q.lifecycle,false) and disk.lastStand.state=='declined'
            and disk.lastStand.declinedStop==d.location,'host decline is not durable')
        check(not r.lastStand.capture,'durable decline did not release Source modal')
        print('LAN_ADVENTURE_OFFER_DECLINED hostInput='..(touch and 'touch' or 'n')..' durable=true guestStoryInputs=false key='..offerDecision.key)
        file('host.offer.declined',offerDecision.key);offerDecision=nil;progress=nil;stallLogged=false
        return true
    end
    local key=Helpers.ordinaryOffer(d,r.lastStand)
    if not key then return false end
    stopWalk()
    if not offerDecision then
        local life=d.lastStand.lifecycle
        offerDecision={key=key,id=life.entityId,revision=life.revision,at=love.timer.getTime()}
        file('host.offer.pending',key)
        photo('host-adventure-last-stand-offer.png',function() offerDecision.captured=true end)
        return true
    end
    check(offerDecision.key==key,'ordinary offer changed before host decision')
    check(love.timer.getTime()-offerDecision.at<20,'guest did not observe the actual host offer')
    if not offerDecision.captured or file('guest.offer.observed')~=key then return true end
    -- Source offerButtons(960,720): the authored Not Now button. Keyboard
    -- mode uses the same production binding; neither path changes saved flags.
    offerDecision.sent=true
    if touch then press({x=500,y=602,w=210,h=50}) else button('n') end
    return true
end
local function hostUpdate(lp)
    if lp:pending() then menu(); click('approve'); back() end
    local d=c.runtime.saveData; local link=lp.network and lp.network.link
    if stage=='resumed' then
        if link and link.phase=='ready' and file('guest.reload.taken') then
            local own=Players.forActor(d,'companion'); local found=false
            for _,item in pairs(own.itemSlots.inventory) do if item.id==storedId then found=true end end
            check(found,'reloaded guest did not receive exact stored identity'); check(not next(travelChest(d).storage),'stored item remained duplicated')
            check(lp.authority:checkpointNow(),'final post-rehost checkpoint failed'); sameSignature(assert(Save.read(1)),signature(d),'final save differs',true)
            file('host.done','true'); stage='done'
        end
        return
    end
    if stage=='done' then if not link then finish() end; return end
    if not link or link.phase~='ready' then return end
    if c.runtime.saveData.roamingEncounter then stopWalk(); app.draw(); press(c.ui.roamingEncounterControls[1]); return end
    if battlePilot() then return end
    if stage=='hosting' and file('guest.initial.ready') then
        initialCampaign=d.coop.network.campaignId; initialCompanion=d.coop.network.companionId
        baselineHostWeapon=d.players.host.itemSlots.equipment[1].id; baselineGuestWeapon=d.players.companion.itemSlots.equipment[1].id
        hostControl('leaveTrain'); check(d.scene=='stop','resolved arrival did not leave train'); stage='enter-outskirts'
    elseif stage=='enter-outskirts' and file('guest.stop.ready') then
        if walkTo(875,367,60) then interact(); check(d.scene=='expedition','actual host entrance input failed'); stage='cache-wait' end
    elseif stage=='cache-wait' and file('guest.cache.complete') then
        if battles==0 then stage='seek-battle' else stage='return-town' end
    elseif stage=='seek-battle' then
        local mob=d.expeditions[Areas.SURFACE_ID].mobs['surface-bandit-a']
        check(not mob.dead,'natural cache path somehow defeated all enemies without battle')
        walkTo(mob.x,mob.y,18) -- Waiting within reach lets the real windup start combat.
    elseif stage=='return-town' then
        if walkTo(836,856,55) then
            interact();check(c.runtime.saveData.scene=='stop','actual return-town input failed')
            townWaitStarted=love.timer.getTime();stage='town-offer'
        end
    elseif stage=='town-offer' then
        -- A stationary host lets the original scout approach and offer finish.
        -- hostOfferPilot observes the real modal and uses the host's Not Now
        -- input above; guest trading starts only after that checkpoint clears.
        stopWalk()
        check(love.timer.getTime()-townWaitStarted<45,'natural town offer did not resolve before guest trading')
        local declined=file('host.offer.declined')
        if Helpers.townReady(c.runtime.saveData,c.runtime,declined) and not c.session.checkpointPending
            and not lp.authority.pendingSave and not WorldPause.isPaused(c.runtime,c.ui,c.maintenanceSession) then
            print('LAN_ADVENTURE_TOWN_READY offerDeclined='..declined..' durable=true hostDecision=true guestTradePending=false')
            file('host.town',declined);stage='trade-wait'
        end
    elseif stage=='trade-wait' and file('guest.trade.complete') then
        check(hostAttacks>0 and tonumber(file('guest.attacks') or '0')>0,'both players must actually attack naturally')
        check(actualUses(d.players.host)>0 and actualUses(d.players.companion)>0,'UI clicks did not become owned authoritative attacks')
        local rewards=0; for _,mob in pairs(d.expeditions[Areas.SURFACE_ID].mobs) do
            if mob.rewardResolved then check(mob.dead and mob.hp==0 and mob.rewardReceipt,'natural victory reward lacks settled enemy'); rewards=rewards+1 end
        end
        check(rewards>=1,'natural adventure settled no original enemy rewards')
        check(d.players.host.itemSlots.equipment[1].id==baselineHostWeapon and d.players.companion.itemSlots.equipment[1].id==baselineGuestWeapon,'adventure replaced starter gear')
        stage='board-train'
    elseif stage=='board-train' then
        local x,y=Settlements.trainPoint(d.location)
        -- The illustrated train anchor may lie outside its foot collision mask.
        -- Walk to the ordinary clamped approach and still prove physical reach.
        local approachX,approachY=Settlements.clamp(x,y,d.location)
        if walkTo(approachX,approachY,14) then
            if not captures['host-train-approach.png'] then photo('host-train-approach.png');return end
            app.draw();local selected=c.ui.interaction
            check(Settlements.nearTrain(c.runtime.player.x,c.runtime.player.y,d.location),'host has not physically reached train approach')
            check(selected and selected.kind=='returnTrain','actual train BOARD interaction unavailable: '..tostring(selected and selected.kind))
            local controls=touch and c.getMobileControls();local point=controls and Helpers.touchInteraction('host','stop',controls)
            local hud=c.ui.returnTrain;local hudX,hudY
            if hud then hudX,hudY=coords(hud.x+hud.w/2,hud.y+hud.h/2) end
            print('LAN_ADVENTURE_BOARD xy='..c.runtime.player.x..','..c.runtime.player.y..' anchor='..x..','..y..' approach='..approachX..','..approachY
                ..' interaction='..selected.kind..' point='..tostring(point and point.x)..','..tostring(point and point.y)
                ..' hudLogical='..tostring(hud and hud.x)..','..tostring(hud and hud.y)..','..tostring(hud and hud.w)..','..tostring(hud and hud.h)
                ..' hudPhysical='..tostring(hudX)..','..tostring(hudY)..' hudAcceptance=false'
                ..' checkpoint='..tostring(c.session.checkpointPending)..' state='..c.runtime.state
                ..' dialogue='..tostring(c.runtime.dialogue~=nil)..' inventory='..tostring(c.runtime.inventoryOpen)..' trade='..tostring(c.runtime.tradeOpen)
                ..' pose='..tostring(c.runtime.poseMenu)..' radio='..tostring(c.ui.radioOpen)..' helpDialogue='..tostring(c.runtime.helpDialogue~=nil)
                ..' options='..tostring(c.ui.optionsOpen)..' escapeMenu='..tostring(c.ui.escMenuOpen))
            local result=interact()
            print('LAN_ADVENTURE_BOARD_RESULT callback='..tostring(result)..' runtimeScene='..c.runtime.scene
                ..' campaignScene='..c.runtime.saveData.scene..' checkpoint='..tostring(c.session.checkpointPending))
            check(c.runtime.scene=='train' and c.runtime.saveData.scene=='train','actual contextual BOARD input failed')
            file('host.train','true');stage='store-wait'
        end
    elseif stage=='store-wait' and file('guest.stored') then
        storedId=file('stored.id'); local found=false; local chest=travelChest(d)
        for _,item in pairs(chest.storageInstances or {}) do if item.id==storedId then
            check(Helpers.same(item,assert(Codec.decode(file('stored.record'))),false),'train storage changed exact original weapon record');found=true
        end end
        check(found,'canonical travel chest did not store exact acquired identity')
        check(not d.tacticalBattle and not d.roamingEncounter and d.coop.network.campaignId==initialCampaign and d.coop.network.companionId==initialCompanion,'adventure changed campaign or left combat pending')
        check(lp.authority:checkpointNow(),'whole-adventure disk checkpoint failed')
        checkpoint=signature(assert(Save.read(1))); sameSignature(d,checkpoint,'RAM differs from durable whole-adventure checkpoint',true)
        file('resume.expected',checkpoint); file('resume.public',publicSignature(assert(Save.read(1)))); file('resume.session',lp.authority.sessionId)
        file('host.restart.saved','true'); photo('host-adventure-saved.png',function() stage='restart' end)
    elseif stage=='restart' and file('guest.restart.ready') then
        if restart then
            finished=true; stopWalk(); print('LAN_SMOKE_RESTART role=host adventureSaved=true ownedItems=true naturalCombat=true'); love.event.quit(42)
        else menu(); click('stop'); c.runtime.state='slots'; c.runtime.saveData=nil; c.runtime.selectedSlot=nil; hostSavedEntry();
            file('host.resumed.session',lp.authority.sessionId); stage='resumed' end
    end
end
local function guestUpdate(lp)
    if stage=='restart-wait' then
        local expected=file('host.resumed.session')
        if expected and Helpers.newSession(lp.network,oldSession,expected) and Helpers.reliableView(lp) then
            -- The join menu suppresses movement/actions. Close it through the
            -- real control before waiting for the fresh motion acknowledgement.
            if lp.menuOpen then back(); return end
            if ready() then
                samePublic(lp.replica.data,file('resume.public'),'re-admission changed saved adventure state',false)
                check(lp.network.campaignId==initialCampaign and lp.network.credential.companionId==initialCompanion,'re-admission replaced saved credentials')
                if purchasedId then check(ownIdentity(purchasedId),'re-admission lost the exact normal purchase')
                else check(ownItem(purchasedName),'re-admission lost the purchased supply') end
                photo('guest-adventure-reloaded.png',function() stage='take-reloaded' end)
            end
        elseif expected and not restartRequested and (not lp.network or lp.network.sessionId~=expected) then
            if lp.network then menu(); click('leave') end
            menu(); click('join'); restartRequested=true
        end
        return
    end
    if lp.error then error('Local Play adventure: '..tostring(lp.error)) end
    local view=lp.clientView; if not view or not view.ready then return end
    local q=view.runtime.saveData.lastStand; local life=q and q.lifecycle
    local offerKey=life and life.mode=='offer' and life.entityId..':'..life.revision
    if offerKey and Helpers.reliableView(lp) then
        stopWalk()
        if file('host.offer.pending')==offerKey and file('guest.offer.observed')~=offerKey then
            check(view.lastStand:available(),'guest did not present the actual passive offer')
            local nextId=lp.network.nextRequestId
            button('n');button('y')
            check(lp.network.nextRequestId==nextId and life.mode=='offer' and not lp.network.pendingCommand,
                'guest story keys emitted a command or progressed the offer')
            photo('guest-adventure-last-stand-offer.png',function() file('guest.offer.observed',offerKey) end)
        end
        return
    end
    if stage=='joining' and Helpers.reliableView(lp) and lp.menuOpen then back(); return end
    if stage=='joining' and ready() then
        initialCampaign=lp.network.campaignId; initialCompanion=lp.network.credential.companionId
        local weapon=view.runtime.saveData.itemSlots.equipment[2]
        check(weapon and weapon.name=='trail-slingshot','normal starter slingshot absent at join'); storedId=weapon.id;file('stored.id',storedId)
        baselineFood=view.runtime.saveData.resources.food; file('guest.initial.ready','true'); stage='wait-stop'
    end
    if completeRequest(lp) then return end
    if not Helpers.actionReady(love.timer.getTime(),lastAction) then return end
    if battlePilot() then return end
    if not ready() then stopWalk(); return end
    local d=data()
    if stage=='wait-stop' and d.scene=='stop' then file('guest.stop.ready','true'); stage='cache-route'
    elseif stage=='cache-route' and d.scene=='expedition' then
        if walkTo(1520,467,50) then
            local frame=lp.motionFrame
            print('LAN_ADVENTURE_CACHE_INPUT sceneEpoch='..view.epoch..' motionId='..view.motionId..' serial='..frame.serial
                ..' ack='..frame.ack..' sent='..view.sequence..' inputActive='..tostring(frame.inputActive)
                ..' predicted='..Helpers.reachTrace(d,view.runtime.player,1520,467,64,Areas)
                ..' checked='..Helpers.reachTrace(d,require('game.net.movement').unpackActor(frame.companion),1520,467,64,Areas))
            check(view:actionLabel()=='SEARCH RUIN CHEST','actual cache affordance missing')
            interact(); check(view.expedition.pending,'cache activation did not request authority'); awaitRequest(view.expedition,'cache-open')
        end
    elseif stage=='cache-open' then
        check(view.runtime.chestOpen,'durable cache did not open owned UI'); app.draw()
        local chest=view.runtime.activeChest; chestId=chest.entityId
        local index; for i,name in pairs(chest.storage) do if name=='water-bottle' then index=i end end
        check(index,'authored water missing'); bagPress(Inventory.chestSlotRect(index)); app.draw(); bagPress(view.inventory.transferButton)
        awaitRequest(view.inventory,'take-ration',function()
            check(ownItem('water-bottle') and not data().expeditions[Areas.SURFACE_ID].chests['surface-cache'].storage[index],'actual water transfer absent')
            supplies.water=true;cachedItems=cachedItems+1
        end)
    elseif stage=='take-ration' then
        app.draw(); local index; for i,name in pairs(view.runtime.activeChest.storage) do if name=='food-ration' then index=i end end
        check(index,'authored ration missing'); bagPress(Inventory.chestSlotRect(index)); app.draw(); bagPress(view.inventory.transferButton)
        awaitRequest(view.inventory,'take-bandage',function()
            check(ownItem('food-ration') and not data().expeditions[Areas.SURFACE_ID].chests['surface-cache'].storage[index],'actual ration transfer absent')
            supplies.ration=true;cachedItems=cachedItems+1
        end)
    elseif stage=='take-bandage' then
        app.draw(); local index; for i,name in pairs(view.runtime.activeChest.storage) do if name=='field-bandage-roll' then index=i end end
        check(index,'authored bandage missing'); bagPress(Inventory.chestSlotRect(index)); app.draw(); bagPress(view.inventory.transferButton)
        awaitRequest(view.inventory,'consume-ration',function()
            check(ownItem('field-bandage-roll') and not data().expeditions[Areas.SURFACE_ID].chests['surface-cache'].storage[index],'actual bandage transfer absent')
            supplies.bandage=true;cachedItems=cachedItems+1
        end)
    elseif stage=='consume-ration' then
        app.draw(); local index=ownItem('food-ration'); bagPress(inventorySlot(index)); app.draw(); bagPress(view.ui.consume)
        awaitRequest(view.inventory,'cache-complete',function() check(not ownItem('food-ration') and data().resources.food==baselineFood+3,'guest assistance cost/resource changed'); consumed=true end)
    elseif stage=='cache-complete' then
        check(cachedItems==3 and consumed and supplies.water and supplies.ration and supplies.bandage,'authored cache/assistance incomplete')
        app.draw(); bagPress(view.inventory.closeButton)
        file('guest.cache.complete','true'); photo('guest-cache-help.png',function() stage='wait-town' end)
    elseif stage=='wait-town' and d.scene=='stop' and file('host.town') then stage='trade-route'
    elseif stage=='trade-route' then
        local npc=view.runtime.npcActor; check(npc,'natural crow merchant actor missing after return')
        if walkTo(npc.x,npc.y,70) then
            app.draw(); check(view.trade:nearest(),'naturally generated merchant not reachable')
            if view.ui.guestTrade then press(view.ui.guestTrade) else interact() end
            check(view.runtime.tradeOpen,'actual Trade interaction failed'); stage='trade-select'
        end
    elseif stage=='trade-select' then
        app.draw(); local source=view.trade:source(); check(source,'natural trade source missing')
        local cheapest,price
        for i=1,#source.stock do local name,entry=Trade.stockItem(source,i)
            if name and Trade.deliveryTarget(d,c.catalog,source,name,entry)=='inventory' then
                local cost=Trade.buyPrice(d,c.catalog,source,i); if not price or cost<price then cheapest,price=i,cost end
            end
        end
        check(cheapest and price<=d.scrap,'actual victory reward cannot afford a normal inventory listing')
        if not view.ui.tradeBuy[cheapest] then press(view.ui.tradeBuyNext); return end
        tradeIndex=cheapest; press(view.ui.tradeBuy[tradeIndex]); check(view.trade.quote,'actual trade quote missing'); stage='trade-confirm'
    elseif stage=='trade-confirm' then
        app.draw(); local before=d.scrap; local quoted=view.trade.quote.args.quotedPrice
        local quotedItem=view.trade.quote.args.quotedItem; local beforeIds=Helpers.identities(d.itemSlots.inventory)
        local beforeNames=Helpers.copy(d.inventory)
        press(view.ui.guestTradeConfirm)
        awaitRequest(view.trade,'trade-complete',function(reply)
            local actual=data(); check(actual.scrap==before-quoted and reply.details.price==quoted,'normal purchase price repeated or changed')
            check(reply.details.item==quotedItem,'actual purchase delivered a different listing')
            local slot,id=Helpers.purchasedSlot(beforeNames,beforeIds,actual.inventory,actual.itemSlots.inventory,reply.details,Items.isGear)
            check(slot,'normal inventory purchase did not add exactly one correct new slot');purchasedName=reply.details.item;purchasedId=id
            file('purchased.id',purchasedId or 'unidentified-supply');file('purchased.name',purchasedName)
        end)
    elseif stage=='trade-complete' then
        photo('guest-natural-trade.png',function() view.trade:close(); file('guest.trade.complete','true'); stage='wait-train' end)
    elseif stage=='wait-train' and d.scene=='train' and file('host.train') then stage='store-route'
    elseif stage=='store-route' or stage=='take-reloaded' then
        local chest=travelChest(d)
        if walkTo(chest.x,chest.y,50) then interact(); check(view.runtime.chestOpen,'original travel chest did not open'); stage=stage=='store-route' and 'store-weapon' or 'take-weapon' end
    elseif stage=='store-weapon' then
        app.draw(); local instance=d.itemSlots.equipment[2];check(instance and instance.id==storedId,'original slingshot replaced before storage')
        storedRecord=Helpers.copy(instance);storedAmmo=Helpers.copy(d.ammo);file('stored.record',assert(Codec.encode(storedRecord)))
        bagPress(touch and Inventory.mobileEquipmentSlotRect(2) or Inventory.equipmentSlotRect(2));app.draw();bagPress(view.inventory.transferButton)
        awaitRequest(view.inventory,'stored',function()
            check(not data().itemSlots.equipment[2] and not data().equipment[2],'slingshot remained duplicated in equipment')
            check(Helpers.same(data().ammo,storedAmmo,false),'storing slingshot changed ammunition')
        end)
    elseif stage=='stored' then
        app.draw(); bagPress(view.inventory.closeButton); file('guest.stored','true'); oldSession=lp.network.sessionId
        photo('guest-adventure-stored.png',function() stage='wait-restart' end)
    elseif stage=='wait-restart' and file('host.restart.saved') then
        samePublic(lp.replica.data,file('resume.public'),'guest final durable baseline differs',true)
        file('guest.restart.ready','true'); stage='restart-wait'
    elseif stage=='take-weapon' then
        app.draw(); local index;for i,record in pairs(view.runtime.activeChest.storageInstances) do if record.id==storedId then index=i;check(Helpers.same(record,storedRecord,false),'stored weapon record changed') end end
        check(index,'original slingshot missing after true disk reload'); bagPress(Inventory.chestSlotRect(index)); app.draw(); bagPress(view.inventory.transferButton)
        awaitRequest(view.inventory,'taken',function()
            local actual=data(); local _,item=ownIdentity(storedId);check(item and Helpers.same(item,storedRecord,false),'disk/rehost changed original exact weapon')
            check(Helpers.same(actual.ammo,storedAmmo,false),'disk/rehost changed retained ammunition')
            check(lp.network.campaignId==initialCampaign and lp.network.credential.companionId==initialCompanion,'rehost replaced campaign/member')
        end)
    elseif stage=='taken' then
        app.draw(); bagPress(view.inventory.closeButton); file('guest.reload.taken','true'); photo('guest-reloaded-item.png',function() stage='done' end)
    elseif stage=='done' and file('host.done') then menu(); click('leave'); finish() end
end
local function update(dt)
    if finished then return end
    check(love.timer.getTime()-started<350,'adventure deadline stage='..tostring(stage))
    -- Real measured delta only. No timer, HP, AI, RNG or battle fast-forward.
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay; if lp.focused==false then app.focus(true) end
    check(not stallFailure,'bounded adventure movement stall: '..tostring(stallFailure))
    if role=='host' and not capture and not capturePending and hostOfferPilot(lp) then return end
    if role=='host' and navigation and not c.runtime.battle and not offerDecision and not capture and not capturePending then
        local player=c.runtime.player;local now=love.timer.getTime();local held
        progress,held=Helpers.progress(progress,stage,player.x,player.y,now)
        if held>=3 and not stallLogged then
            stallLogged=true
            local npc=c.runtime.npcActor;local ui,r=c.ui,c.runtime;local frame=lp.motion
            local controls=touch and c.getMobileControls();local owner=controls and controls.touches['adventure-walk']
            local ax,ay=0,0;if controls then ax,ay=controls:movement() end
            local t,p=touchTrace or {},touchLastPress or {}
            print('LAN_ADVENTURE_STALL stage='..stage..' xy='..player.x..','..player.y..' waypoint='..navigation.nx..','..navigation.ny
                ..' target='..navigation.x..','..navigation.y..' heldSeconds='..held..' paused='..tostring(WorldPause.isPaused(r,ui,c.maintenanceSession))
                ..' simulationPaused='..tostring(WorldPause.isSimulationPaused(r,ui,c.maintenanceSession))
                ..' injected='..tostring(love.keyboard.isDown==injectedKeyboard)..' sampledASWD='
                ..tostring(love.keyboard.isDown('a'))..','..tostring(love.keyboard.isDown('s'))..','..tostring(love.keyboard.isDown('w'))..','..tostring(love.keyboard.isDown('d'))
                ..' desiredASWD='..tostring(movement.a)..','..tostring(movement.s)..','..tostring(movement.w)..','..tostring(movement.d)
                ..' intent='..tostring(player.intentX)..','..tostring(player.intentY)..' velocity='..tostring(player.velocityX)..','..tostring(player.velocityY)
                ..' blocked='..tostring(player.blocked)..' speed='..tostring(player.speed)..' gait='..tostring(player.gaitSpeedMultiplier)
                ..' state='..r.state..' runtimeScene='..r.scene..' campaignScene='..r.saveData.scene
                ..' checkpoint='..tostring(c.session.checkpointPending)..' pendingSave='..tostring(lp.authority.pendingSave)
                ..' runtimeCheckpoint='..tostring(r.session and r.session.checkpointPending)
                ..' menu='..tostring(lp.menuOpen)..' focused='..tostring(lp.focused)..' privateInventory='..tostring(r.inventoryOpen)
                ..' map='..tostring(r.mapOpen)..' log='..tostring(r.journeyLogOpen)..' edit='..tostring(r.editMode)..' trade='..tostring(r.tradeOpen)
                ..' pose='..tostring(r.poseMenu)..' options='..tostring(ui.optionsOpen)..' escape='..tostring(ui.escMenuOpen)..' radio='..tostring(ui.radioOpen)
                ..' mobileMenu='..tostring(ui.mobileMenuOpen)..' playerTools='..tostring(ui.playerToolsOpen)
                ..' pendingConfirmation='..tostring(r.pendingConfirmation and r.pendingConfirmation.kind)
                ..' exitPrompt='..tostring(r.exitPrompt~=nil and r.exitPrompt~=false)..' travelConfirm='..tostring(r.travelConfirm)
                ..' maintenance='..tostring(c.maintenanceSession and c.maintenanceSession.open)..' outfitCrafting='..tostring(r.outfitCraftingOpen)
                ..' dialogueType='..type(r.dialogue)..' dialogueTimer='..tostring(type(r.dialogue)=='table' and r.dialogue.timer)
                ..' dialogueSpeaker='..string.format('%q',tostring(type(r.dialogue)=='table' and r.dialogue.speaker))
                ..' dialogueText='..string.format('%q',tostring(type(r.dialogue)=='table' and r.dialogue.text))
                ..' dialogueChoice='..tostring(type(r.dialogue)=='table' and r.dialogue.choice)..' inventoryResult='..tostring(type(r.dialogue)=='table' and r.dialogue.inventoryResult)
                ..' interaction='..tostring(ui.interaction and ui.interaction.kind)..' helpDialogue='..tostring(r.helpDialogue~=nil)..' firstAid='..tostring(r.firstAid~=nil)
                ..' range='..tostring(r.shootingRange~=nil)..' battle='..tostring(r.battle~=nil and r.battle~=false)
                ..' lastStand='..tostring(r.lastStand and r.lastStand.capture)..' ambush='..tostring(r.trainAmbush and r.trainAmbush.phase)
                ..' carTransition='..tostring(r.carTransition~=nil and r.carTransition~=false)..' travel='..tostring(r.travelTransition~=nil and r.travelTransition~=false)
                ..' pressure='..tostring(r.saveData.roamingEncounter~=nil)..' npc='..tostring(npc and npc.x)..','..tostring(npc and npc.y)
                ..' peer='..tostring(lp.network and lp.network.link and lp.network.link.phase)..' readyEpoch='..tostring(frame and frame.readyEpoch)
                ..' mobPaused='..tostring(r.mobPaused)..' touchHeld='..tostring(joystickHeld)..' touchOwner='..tostring(owner and owner.kind)
                ..' joystickOwner='..tostring(controls and controls.joystickTouch)..' touchAxes='..ax..','..ay
                ..' movementActive='..tostring(controls and controls:isMovementActive())..' gameplayActive='..tostring(controls and controls:isGameplayActive())
                ..' pressLogical='..tostring(p.pressLogicalX)..','..tostring(p.pressLogicalY)..' pressPhysical='..tostring(p.pressX)..','..tostring(p.pressY)
                ..' moveLogical='..tostring(t.moveLogicalX)..','..tostring(t.moveLogicalY)..' movePhysical='..tostring(t.moveX)..','..tostring(t.moveY)
                ..' pressResult='..tostring(p.pressResult)..' moveResult='..tostring(t.moveResult))
        end
        if held>=6 then
            photo('host-stall-'..stage..'.png',function() stallFailure=stage end)
            return
        end
    else progress=nil;stallLogged=false end
    if love.timer.getTime()-lastReport>5 then
        lastReport=love.timer.getTime(); local r=role=='host' and c.runtime or lp.clientView and lp.clientView.runtime
        print('LAN_ADVENTURE_PROGRESS role='..role..' stage='..stage..' scene='..tostring(r and r.scene)
            ..' xy='..tostring(r and r.player and r.player.x)..','..tostring(r and r.player and r.player.y)
            ..' link='..tostring(lp.network and lp.network.status)..' battles='..battles..' request='..tostring(request))
    end
    if capture or capturePending then return end
    if role=='host' then hostUpdate(lp) else guestUpdate(lp) end
end
local function draw()
    if finished or not app then return end; app.draw()
    if capture then
        local name,callback=capture,afterCapture; capture=nil; afterCapture=nil; capturePending=true
        love.graphics.captureScreenshot(function(pixels)
            pixels:encode('png',name); captures[name]=true; capturePending=false; if callback then callback() end
        end)
    end
end
local function guarded(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then
        print('LAN_SMOKE_FAILED role='..role..' '..tostring(reason)); finished=true
        if oldKeyboard then love.keyboard.isDown=oldKeyboard end
        if c and c.ui.localPlay then c.ui.localPlay:stop() end; love.event.quit(1)
    end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw() guarded(draw) end
function love.focus(focused) if app then app.focus(focused) end end
