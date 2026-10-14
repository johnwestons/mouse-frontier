-- Two separate LÖVE processes, real ENet sockets and independent save roots.
-- Only this harness auto-approves enrollment. Production approval is local UI.
local Session=require('game.net.session')
io.stdout:setvbuf('no')
local Crypto=require('game.net.crypto')
local Store=require('game.net.credential_store')
local Schema=require('game.save_schema')
local GameState=require('game.net.game_state')
local role=os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE')
local port=assert(tonumber(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT')))
local session,authority,admission,started,finished
local readyCount,issueCount,disconnections,stateUpdates=0,0,0,0
local producer,firstReadyAt,inventoryChanged
local stage='first'; local nextAction; local firstCompanionId; local firstItemId; local disconnectionError
local function check(value,message) assert(value,message) end
local build
local function clock() return love.timer.getTime() end
local function finish()
    if finished then return end; finished=true
    print('LAN_SMOKE_OK role='..role..' ready='..readyCount..' issues='..issueCount..' disconnects='..disconnections..' updates='..stateUpdates)
    if session then session:close() end
    love.event.quit(0)
end
local function startGuest()
    local replica=GameState.replica(); local initialized=false
    return assert(Session.join('127.0.0.1:'..port,{build=build,schema=Schema.CURRENT_VERSION,clock=clock,
        name='LAN test companion',character='cook-mouse.png',
        credentialFor=function(id) local data,reason=Store.load(); return data and Store.find(data,id),reason end,
        store=function(credential) return Store.save(credential) end,
        validate=function(value) return replica:validate(value) end,
        apply=function(value)
            check(replica:apply(value),'production replica apply failed')
            if initialized then
                stateUpdates=stateUpdates+1
                check(replica.data.players.host.inventory[1]==nil and replica.data.players.host.inventory[2]=='orange-rose-vase','inventory delta was not applied')
            else initialized=true; readyCount=readyCount+1 end
            check(replica:actor().character=='cook-mouse.png' and replica:actor().health>0,'missing companion state')
            check(replica.data.location==2 and replica.data.stopLayouts['50'],'late-world state was omitted')
            check(not replica.data.coop.network and not replica.data.itemIdentity and not replica.data.audio.musicVolume,'private state leaked')
            local credentials=assert(Store.load()); check(#credentials.entries==1,'missing durable connection credential')
            if firstCompanionId then check(firstCompanionId==credentials.entries[1].companionId,'rejoin identity changed')
            else firstCompanionId=credentials.entries[1].companionId end
            check(not love.filesystem.getInfo('saves/slot99.lua'),'guest wrote a campaign')
            return true
        end}))
end
local function load()
    started=clock()
    love.math.setRandomSeed(6112026)
    check(role=='host' or role=='guest','invalid smoke role')
    check(Crypto.hash('abc')=='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad','SHA-256 known vector')
    local a,b=assert(Crypto.token()),assert(Crypto.token())
    check(Crypto.isHex(a,64) and a~=b,'OS entropy unavailable or repeated')
    local compatibility=assert(require('game.net.compatibility').compute())
    build=compatibility.build
    print('LAN_SMOKE_COMPATIBILITY files='..compatibility.files..' bytes='..compatibility.bytes)
    if role=='guest' then session=startGuest(); return end
    local F=require('fixture'); local Save=require('game.save')
    local data=F.campaign(2,{scene='train'})
    producer=GameState.producer()
    data.npcRoster={'cook-mouse.png','scout-frog.png'}
    for stop=1,50 do data.location=stop; require('game.stops').ensure(data,require('game.catalog'),'stop') end
    data.location=2
    authority=require('game.coop_authority').new({campaign=data,sessionId='lan-engine-smoke',clock=clock,
        checkpoint=function(value) return Save.write(99,value) end})
    require('game.coop_inventory').install(authority,{catalog=require('game.catalog'),car={x=0,y=0},
        actorState=function() return {screen='game',scene='train',x=200,y=250} end})
    admission=assert(require('game.coop_admission').new(authority,{catalog=require('game.catalog'),
        allowedCharacters={['cook-mouse.png']=true},placeCompanion=function(value)
            value.players.companion.playerX=240; value.players.companion.playerY=250; return true
        end}))
    session=assert(Session.host({port=port,bind='127.0.0.1',build=build,schema=Schema.CURRENT_VERSION,clock=clock,
        sessionId=authority.sessionId,campaignId=data.coop.network.campaignId,generationBase=authority.lastGeneration or 0,
        preflight=function() return admission:preflight() end,
        authenticate=function(value) return admission:authenticate(value) end,
        issue=function(request) issueCount=issueCount+1; return admission:issue(request) end,
        revision=function() return producer.revision,data.coop.sceneEpoch end,
        snapshot=function()
            local startedAt=clock()
            local message,reason=producer:capture(data,true); check(message,reason)
            local transfer=assert(require('game.net.baseline').pack(message,1))
            check(transfer.header.parts>1,'production baseline did not exercise chunking')
            print('LAN_SMOKE_BASELINE bytes='..transfer.header.bytes..' parts='..transfer.header.parts..' seconds='..(clock()-startedAt))
            return message
        end,
        update=function()
            if producer.current.view.coop.revision==data.coop.revision then return nil end
            local message,reason=producer:capture(data); check(message,reason)
            check(message.mode=='delta' and #message.domains==2,'update sent unchanged domains')
            stateUpdates=stateUpdates+1; return message
        end,
        ready=function(generation)
            authority:admit('companion',generation); admission:forgetPending(generation)
            local loaded=assert(Save.read(99)); check(loaded.coop.network.bindingVersion==1,'rejoin rebound credentials')
            local item=loaded.players.companion.itemSlots.equipment[1].id
            if firstItemId then check(firstItemId==item,'rejoin replaced starter kit') else firstItemId=item end
            readyCount=readyCount+1; firstReadyAt=firstReadyAt or clock(); return true
        end,
        disconnected=function(generation,reason)
            print('LAN_SMOKE_DISCONNECT generation='..generation..' reason='..tostring(reason))
            if reason~='peer_disconnected' then disconnectionError=reason end
            disconnections=disconnections+1; authority:disconnect('companion',generation); admission:forgetPending(generation)
        end}))
    print('LAN_SMOKE_LISTENING')
end
local function update()
    if finished then return end
    check(clock()-started<25,'LAN smoke deadline exceeded')
    session:update()
    if role=='host' then
        check(not disconnectionError,disconnectionError)
        check(not session.closed,'host session closed')
        local pending=session:pending()
        if pending then check(session:approve(pending.generation),'host approval failed') end
        if firstReadyAt and not inventoryChanged and clock()-firstReadyAt>.3 then
            local reply=authority:submitLocal('inventory.swap',{source={kind='inventory',index=1},target={kind='inventory',index=2}})
            check(reply.ok,'host inventory command failed')
            -- A slot rearrangement uses the normal host save path rather than
            -- a critical receipt; persist it before testing the rejoin state.
            check(require('game.save').write(99,authority.campaign),'host inventory save failed'); inventoryChanged=true
        end
        if readyCount==2 and disconnections==2 then
            check(issueCount==1,'rejoin issued another credential or kit')
            check(stateUpdates==1,'host failed to publish one dirty-domain update')
            check(not authority.bindings.companion,'disconnected actor still admitted'); finish()
        end
    elseif stage=='waiting' then
        if clock()>=nextAction then session=startGuest(); stage='second'; nextAction=nil end
    elseif session.status=='ready' then
        if not nextAction then nextAction=clock()+(stage=='first' and 5.5 or .3) end
        if clock()>=nextAction then
            if stage=='first' then check(stateUpdates==1,'guest did not receive live inventory update') end
            session:close()
            if stage=='first' then stage='waiting'; nextAction=clock()+.5
            else check(readyCount==2,'guest rejoin did not complete'); finish() end
        end
    else
        check(not session.closed,session.reason or 'guest session closed')
        nextAction=nil
    end
end
local function guarded(fn)
    local ok,reason=xpcall(fn,debug.traceback)
    if not ok then
        print('LAN_SMOKE_FAILED role='..tostring(role)..' '..tostring(reason))
        finished=true; if session then session:close() end; love.event.quit(1)
    end
end
function love.load() guarded(load) end
function love.update() guarded(update) end
