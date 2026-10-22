"""Real authority travel inspection/request, strict DTO and private input UI."""
import unittest
import test_coop_authority_behavior as authority_tests
import test_coop_guest_view_behavior as guest_tests
import test_coop_local_play_behavior as local_play_tests
import test_coop_scenes_behavior as scene_tests


class TravelAuthorityTests(unittest.TestCase):
    setUp=authority_tests.CoopAuthorityTests.setUp

    def travel(self):
        self.lua.execute('''
            Requests=require('game.coop_travel_requests');Results=require('game.net.travel_request_results')
            Codec=require('game.net.codec');Records=require('game.net.state_records')
            now=10;writes=0;authority.clock=function()return now end
            authority.checkpoint=function()writes=writes+1;return true end
            data.scene='train';data.stopped=true;data.coop.revision=1
            states.companion.movementReady=true;states.companion.motionId=4
            context={catalog=Catalog,actorState=function(id)return states[id]end}
            Requests.install(authority,context)
            local function map(value)
                if type(value)~='table'then return value end
                local result={};for key,item in pairs(value)do result[type(key)..':'..tostring(key)]=map(item)end;return result
            end
            function bytes(value)return assert(Codec.encode(map(value),
                {maxBytes=1000000,maxDepth=32,maxEntries=200000,maxStringBytes=4096}))end
            function args(action,quote)return{action=action,motionId=4,quote=quote}end
            function quote(result)
                local q={};for _,key in ipairs({'from','to','food','water','coal','sourceRevision'})do q[key]=result[key]end;return q
            end
            function inspect()
                local request=assert(authority:prepareRequest('companion','progression.request',args('inspect')))
                local result=run('companion',request,authority.bindings.companion);assert(result.ok,result.reason);return result.result,request,result
            end
            function depart(q)
                local req=assert(authority:prepareRequest('companion','progression.request',args('depart',q)))
                return run('companion',req,authority.bindings.companion),req
            end
        ''')

    def test_inspection_matches_actual_host_travel_rules_not_guest_traits_without_any_campaign_write(self):
        self.travel()
        self.lua.execute('''
            data.players.host.trait={food=.8,water=.9,coal=.7};data.players.companion.trait={food=3,water=3,coal=3}
            data.engineLevel=2;data.maintenance.condition=22
            data.passengers={{npc='courier.png',job='navigator',origin=1,destination=25}}
            data.trainCars={'living-car','sleeper'};assert(Entities.ensure(data))
            local original=bytes(data);local seed=authority.randomSeed
            local result=inspect();local scratch=assert(Schema.copy(data));Players.attachHost(scratch)
            local cost=require('game.progression_balance').travelCost(scratch,require('game.engine_upgrades'),
                require('game.maintenance'),Catalog.characterTraitProfiles[1],require('game.train_upgrade_balance'))
            for _,key in ipairs({'food','water','coal','terrain','passengers','passengerLoad','maintenanceCoal','navigatorSaved'})do
                assert(result[key]==cost[key],key)end
            assert(result.from==20 and result.to==21 and result.sourceRevision==1)
            assert(result.serial==0 and not result.requested and not result.already)
            assert(bytes(data)==original and writes==0 and not authority.pendingSave and authority.randomSeed==seed)
            assert(not authority.activityState.travelRequests and Schema.validate(data))
        ''')

    def test_departure_request_notifies_once_without_payment_save_revision_rng_or_scene_effect(self):
        self.travel()
        self.lua.execute('''
            local original=bytes(data);local result=inspect();local before=authority.activityState
            local reply,req=depart(quote(result));assert(reply.ok and not reply.durable and not reply.savePending)
            local notice=Requests.notice(authority,context);assert(notice and notice.to==21 and notice.serial==1)
            assert(authority.activityState~=before and not before.travelRequests and not next(authority.activityState.resources))
            assert(reply.revision==1 and not next(reply.revisions) and data.coop.revision==1)
            assert(bytes(data)==original and writes==0 and not data.coop.journey)
            now=12;local replay=run('companion',req);assert(replay.ok and replay.result.serial==1)
            assert(authority.activityState.travelRequests.pending.expiresAt==25)
            local again=depart(quote(result));assert(again.ok and again.result.already and again.result.serial==1)
            assert(authority.activityState.travelRequests.nextSerial==2 and bytes(data)==original)
            notice.food=999;assert(Requests.notice(authority,context).food~=999)
            assert(not Requests.dismiss(authority,2) and Requests.dismiss(authority,1))
            assert(not Requests.notice(authority,context));now=16
            local nextReply=depart(quote(result));assert(nextReply.ok and nextReply.result.serial==2)
            assert(bytes(data)==original and writes==0)
        ''')

    def test_replay_after_expiry_or_dismiss_does_not_renotify_and_new_requests_are_cooldown_bounded(self):
        self.travel()
        self.lua.execute('''
            local m=inspect();local result,req=depart(quote(m));assert(result.ok)
            assert(Requests.dismiss(authority,result.result.serial));now=11
            assert(run('companion',req).ok and not Requests.notice(authority,context))
            local request=assert(authority:prepareRequest('companion','progression.request',args('depart',quote(m))))
            assert(run('companion',request).reason=='request_cooldown')
            assert(authority.activityState.travelRequests.nextSerial==2)
            now=30;assert(depart(quote(m)).ok);now=46;assert(not Requests.notice(authority,context))
            assert(run('companion',req).ok and not Requests.notice(authority,context))
        ''')

    def test_stale_quote_revision_motion_generation_and_scene_cannot_request_or_replay_effects(self):
        self.travel()
        self.lua.execute('''
            local m=inspect();local q=quote(m)
            local request=assert(authority:prepareRequest('companion','progression.request',args('depart',q)))
            data.resources.food=data.resources.food+1;data.coop.revisions.resources=1
            assert(run('companion',request).reason=='stale_revision' and not Requests.notice(authority,context))
            data.coop.revisions.resources=0;data.coop.revision=2
            local prepared,reason=authority:prepareRequest('companion','progression.request',args('depart',q))
            assert(not prepared and reason=='travel_quote_changed')
            q.food=q.food+1;q.sourceRevision=2
            prepared,reason=authority:prepareRequest('companion','progression.request',args('depart',q))
            assert(not prepared and reason=='travel_quote_changed')
            m=inspect();request=assert(authority:prepareRequest('companion','progression.request',args('depart',quote(m))))
            assert(run('companion',request,2).reason=='unbound_peer')
            states.companion.motionId=5;assert(run('companion',request).reason=='travel_unavailable')
            states.companion.motionId=4;m=inspect();request=assert(authority:prepareRequest('companion','progression.request',args('depart',quote(m))))
            data.coop.sceneEpoch=data.coop.sceneEpoch+1;assert(run('companion',request).reason=='stale_scene')
            assert(not authority.activityState.travelRequests)
        ''')

    def test_only_host_can_depart_even_after_request_and_notification_clears_on_rebind_or_travel(self):
        self.travel()
        self.lua.execute('''
            local m=inspect();local reply=depart(quote(m));assert(reply.ok)
            local forbidden,reason=authority:prepareRequest('companion','travel.depart',{})
            assert(not forbidden and reason=='host_only' and not data.coop.journey)
            authority:disconnect('companion',1);authority:admit('companion',2)
            assert(not Requests.notice(authority,context))
            now=16
            m=inspect();local req=assert(authority:prepareRequest('companion','progression.request',args('depart',quote(m))))
            assert(run('companion',req,2).ok);data.coop.journey={from=20,to=21}
            assert(not Requests.notice(authority,context));assert(writes==0)
        ''')

    def test_modal_activity_and_unready_guest_fail_closed_without_transient_or_campaign_changes(self):
        self.travel()
        self.lua.execute('''
            local original=bytes(data)
            for _,field in ipairs({'traveling','encounterActive','changingCar','activityBlocked'})do
                states.companion[field]=true
                local req,reason=authority:prepareRequest('companion','progression.request',args('inspect'))
                assert(not req and reason=='travel_unavailable');states.companion[field]=nil
            end
            states.companion.movementReady=false
            local req,reason=authority:prepareRequest('companion','progression.request',args('inspect'))
            assert(not req and reason=='travel_unavailable');states.companion.movementReady=true
            for key,value in pairs({actorId='host',cost=0,clock=0,scene='stop',to=50})do
                local valueArgs=args('inspect');valueArgs[key]=value
                req,reason=authority:prepareRequest('companion','progression.request',valueArgs)
                assert(not req and reason=='invalid_args')
            end
            assert(bytes(data)==original and not authority.activityState.travelRequests and writes==0)
        ''')

    def test_authority_transient_escape_hatch_rejects_any_campaign_prepare_apply_mutation_and_other_commands(self):
        self.travel()
        self.lua.execute('''
            local original=bytes(data)
            authority.handlers['progression.request']=function(d,id,a,t)
                t.state.testTransient=true
                return{scopes=Requests.scopes(),checkpoint=false,transientOnly=true,effects={},apply=function()
                    d.resources.food=d.resources.food+1;return{ok=true}end}
            end
            local req=assert(authority:prepareRequest('companion','progression.request',args('inspect')))
            assert(run('companion',req).reason=='invalid_transient_mutation')
            assert(bytes(data)==original and not authority.activityState.testTransient and writes==0)
            authority.handlers['progression.request']=function(d)
                d.coop.randomState=77
                return{scopes=Requests.scopes(),checkpoint=false,transientOnly=true,effects={},apply=function()return{}end}
            end
            req=assert(authority:prepareRequest('companion','progression.request',args('inspect')))
            assert(run('companion',req).reason=='invalid_transient_mutation' and bytes(data)==original)
            authority.handlers['inventory.swap']=function()
                return{scopes={'player:companion'},checkpoint=false,transientOnly=true,effects={},apply=function()return{}end}
            end
            local denied,reason=authority:prepareRequest('companion','inventory.swap',{})
            assert(not denied and reason=='invalid_handler')
            authority.handlers['progression.request']=function(d,id,a,t)
                return{scopes=Requests.scopes(),checkpoint=false,transientOnly=true,effects={},apply=function()
                    t.state.resources={fake={actorId='companion'}};return Requests.inspect(d,Catalog)end}
            end
            req=assert(authority:prepareRequest('companion','progression.request',args('inspect')))
            assert(run('companion',req).reason=='invalid_transient_mutation' and not next(authority.activityState.resources))
            authority.handlers['progression.request']=function(d,id,a,t)
                return{scopes=Requests.scopes(),checkpoint=false,transientOnly=true,effects={},apply=function()
                    t.state.travelRequests={nextSerial=2};local result=Requests.inspect(d,Catalog);result.privateSecret='hidden';return result end}
            end
            req=assert(authority:prepareRequest('companion','progression.request',args('inspect')))
            assert(run('companion',req).reason=='invalid_public_result' and not authority.activityState.travelRequests)
        ''')

    def test_new_strict_public_result_rejects_hidden_data_invalid_costs_and_fits_control_packet(self):
        self.travel()
        self.lua.execute('''
            local m,req,reply=inspect();local Wire=require('game.net.commands');local P=require('game.net.protocol')
            local message=assert(Wire.outcome(authority.sessionId,req.requestId,reply,'progression.request'))
            assert(Wire.result(message) and #assert(P.encode(message,P.CONTROL))<=1200 and P.VERSION==32)
            assert(message.details.available.food==data.resources.food)
            local copy=Results.project(m);copy.futureEvent='spoiler';assert(not Results.valid(copy))
            copy=Results.project(m);copy.to=50;assert(not Results.valid(copy))
            copy=Results.project(m);copy.food=-1;assert(not Results.valid(copy))
            copy=Results.project(m);copy.available.food=0/0;assert(not Results.valid(copy))
            copy=Results.project(m);copy.affordable=not copy.affordable;assert(not Results.valid(copy))
            message.details.missing.food=999;assert(not Wire.result(message))
        ''')

    def test_host_notice_uses_current_costs_after_help_changes_train_or_supplies_without_reissuing_request(self):
        self.travel()
        self.lua.execute('''
            local m=inspect();assert(depart(quote(m)).ok)
            data.resources.food=0;data.engineLevel=2;data.maintenance.condition=20
            data.coop.revision=data.coop.revision+1
            local before=bytes(data);local notice=Requests.notice(authority,context)
            local current=Requests.inspect(data,Catalog)
            assert(notice.serial==1 and notice.food==current.food and notice.coal==current.coal)
            assert(notice.available.food==0 and notice.missing.food==current.food and not notice.affordable)
            assert(bytes(data)==before and authority.activityState.travelRequests.nextSerial==2 and writes==0)
        ''')


class GuestTravelInputTests(unittest.TestCase):
    setUp=guest_tests.GuestViewTests.setUp

    def travel(self):
        self.lua.execute('''
            ready();controller.network.status='ready';controller.network.sessionId='guest-test'
            local calls={};travelCalls=calls
            function controller.network:submitCommand(name,args,epoch,expected)
                calls[#calls+1]={name=name,args=args,epoch=epoch,expected=expected}
                self.pendingCommand={requestId=#calls,command=name};return #calls
            end
            data.coop.revision=1;view.runtime.saveData.coop.revision=1
            model={from=data.location,to=data.location+1,food=1,water=2,coal=3,terrain='plains',
                passengers=0,passengerLoad=0,maintenanceCoal=0,navigatorSaved=0,
                available={food=10,water=10,coal=10},missing={food=0,water=0,coal=0},affordable=true,
                sourceRevision=1,serial=0,requested=false,already=false}
            function reply(details,reason)
                controller.network.pendingCommand=nil
                controller.network.lastCommandResult={sessionId='guest-test',requestId=#calls,command='progression.request',
                    ok=reason==nil,reason=reason,revision=1,durable=false,savePending=false,details=details}
            end
        ''')

    def test_root_keyboard_route_blocks_actions_reads_host_quote_and_only_submits_request(self):
        self.travel()
        self.lua.execute('''
            view:keypressed('v');assert(view.travel.opened and #travelCalls==1 and travelCalls[1].args.action=='inspect')
            assert(not view:inputAllowed() and not view.runtime.inventoryOpen)
            assert(not mobile.options.cameraGesturesActive() and not mobile.options.backpackVisible())
            view:keypressed('i');assert(not view.runtime.inventoryOpen and #travelCalls==1)
            view.travel:update();assert(view.travel.opened and view.travel.pending)
            reply(model);view.travel:update();assert(view.travel.model.food==1 and not view.travel.pending)
            view:keypressed('return');assert(#travelCalls==2 and travelCalls[2].name=='progression.request')
            assert(travelCalls[2].args.action=='depart' and travelCalls[2].args.quote.coal==3)
            assert(not data.coop.journey and controller.menuOpen==false)
            local result=require('game.net.travel_request_results').project(model);result.serial=1;result.requested=true
            reply(result);view.travel:update();assert(view.travel.notice=='Request sent. The host chooses when to depart.')
            view:keypressed('escape');assert(not view.travel.opened and not view.travel.model and not data.coop.journey)
        ''')

    def test_actual_root_mouse_touch_and_canonical_controller_menu_actions_never_call_story(self):
        self.travel()
        self.lua.execute('''
            love={graphics={getDimensions=function()return 960,720 end}}
            view.ui.guestTravel={x=764,y=488,w=180,h=46}
            view:mousepressed(800,510,1,false);assert(view.travel.opened);reply(model);view.travel:update()
            view.travel.controls={{x=228,y=440,w=504,h=44},{x=228,y=492,w=243,h=44},{x=489,y=492,w=243,h=44}}
            view:touchpressed('request',480,462);assert(travelCalls[2].args.action=='depart')
            reply(model);view.travel:update();view:touchpressed('close',600,510);assert(not view.travel.opened)
            view:touchpressed('open',800,510);assert(view.travel.opened)
            reply(model);view.travel:update();local scope,target=view:controllerScope();assert(scope=='menu' and target==view.travel)
            view:gamepadpressed(nil,'b');view:gamepadreleased(nil,'b');assert(not view.travel.opened)
            assert(not data.coop.journey and controller.menuOpen==false)
        ''')

    def test_scene_generation_focus_and_disconnect_clear_private_inspection_not_network_story(self):
        self.travel()
        self.lua.execute('''
            assert(view.travel:open());reply(model);view.travel:update()
            view.motionId=view.motionId+1;view.travel:update();assert(not view.travel.opened)
            view.motionId=controller.motionFrame.motionId
            assert(view.travel:open());view:focus(false);assert(not view.travel.opened)
            view:focus(true);controller.network.pendingCommand=nil
            assert(view.travel:open());reply(model);view.travel:update()
            controller.network.closed=true;view.travel:update();assert(not view.travel.opened)
            assert(not data.coop.journey)
        ''')

    def test_changed_quote_clears_request_control_requires_explicit_refresh_and_no_auto_retry(self):
        self.travel()
        self.lua.execute('''
            assert(view.travel:open());reply(model);view.travel:update();view.travel:submit('depart')
            reply(nil,'travel_quote_changed');view.travel:update();assert(not view.travel.model and not view.travel.pending)
            assert(#travelCalls==2 and not view.travel:submit('depart'))
            view.travel:update();assert(#travelCalls==2)
            assert(view.travel:submit('inspect') and #travelCalls==3)
            assert(travelCalls[3].args.action=='inspect' and not data.coop.journey)
        ''')

    def test_actual_panel_draw_shows_only_host_route_cost_and_private_refresh_close_targets(self):
        self.travel()
        self.lua.execute('''
            local drawn={};local g=setmetatable({getColor=function()return 1,1,1,1 end,getShader=function()return nil end,
                getDimensions=function()return 960,720 end},
                {__index=function()return function()end end})
            love={graphics=g};require('game.typography').drawText=function(_,text)drawn[#drawn+1]=text end
            assert(view.travel:open());reply(model);view.travel:update()
            assert(view.travel:draw() and #view.travel.controls==3)
            local text=table.concat(drawn,'|')
            assert(text:find('STOP '..data.location..' TO STOP '..(data.location+1),1,true) and text:find('COAL 3   /   SHARED 10',1,true))
            assert(text:find('REQUEST DEPARTURE',1,true) and not text:find('reward',1,true))
            local close=view.travel.controls[3];view:mousepressed(close.x+5,close.y+5,1,false)
            assert(not view.travel.opened and not data.coop.journey and #travelCalls==1)
        ''')


class TravelSessionTests(unittest.TestCase):
    setUp=local_play_tests.LocalPlayTests.setUp
    tearDown=local_play_tests.LocalPlayTests.tearDown
    enable_cars=local_play_tests.LocalPlayTests.enable_cars

    def travel(self):
        self.enable_cars()
        self.lua.execute('''
            Requests=require('game.coop_travel_requests')
            commands.setRemoteActorState(function()
                local motion=host.motion
                return {screen='game',scene=data.scene,movementReady=motion and motion.readyEpoch==motion.epoch,
                    motionId=motion and motion.motionId}
            end)
            ready();motionReady()
            function travelAction(action,quote)
                local expected={};for _,scope in ipairs(Requests.scopes())do expected[scope]=guest.replica.data.coop.revisions[scope]or 0 end
                local id=assert(guest.network:submitCommand('progression.request',
                    {action=action,motionId=host.motion.motionId,quote=quote},data.coop.sceneEpoch,expected))
                step(12);return guest.network.lastCommandResult,id
            end
        ''')

    def test_real_session_remote_allowlist_strict_result_delivers_host_notice_without_checkpoint(self):
        self.travel()
        self.lua.execute('''
            local originalWrites=writes;local revision=data.coop.revision;local epoch=data.coop.sceneEpoch
            local resources=Schema.copy(data.resources);local seed=service.randomSeed
            local result=travelAction('inspect');assert(result.ok and not result.durable and result.details.from==2)
            assert(result.revision==revision and writes==originalWrites and not guest.network.pendingCommand)
            local quote={};for _,key in ipairs({'from','to','food','water','coal','sourceRevision'})do quote[key]=result.details[key]end
            result=travelAction('depart',quote);assert(result.ok and result.details.requested and result.details.serial==1)
            local notice=commands.travelRequest();assert(notice and notice.to==3)
            assert(data.resources.food==resources.food and data.resources.water==resources.water and data.resources.coal==resources.coal)
            assert(data.coop.revision==revision and data.coop.sceneEpoch==epoch and service.randomSeed==seed and writes==originalWrites)
            assert(not data.coop.journey and data.scene=='train')
            assert(commands.dismissTravelRequest(notice.serial) and not commands.travelRequest())
            assert(guest.network:submitCommand('travel.depart',{},epoch,{}));step(12)
            assert(guest.network.lastCommandResult.reason=='host_only' and not data.coop.journey)
        ''')

    def test_pending_notifications_do_not_survive_guest_disconnect_rejoin_or_host_session_end(self):
        self.travel()
        self.lua.execute('''
            local result=travelAction('inspect');local quote={}
            for _,key in ipairs({'from','to','food','water','coal','sourceRevision'})do quote[key]=result.details[key]end
            assert(travelAction('depart',quote).ok and commands.travelRequest())
            guest:stop();host:update();assert(not commands.travelRequest())
            assert(guest:join());step(30);assert(guest.phase=='connected')
            assert(not commands.travelRequest() and not data.coop.journey)
            host:stop();assert(not host.network and not host.authority)
        ''')


class HostTravelNotificationTests(unittest.TestCase):
    setUp=local_play_tests.LocalPlayWrapperTests.setUp

    def test_real_host_wrapper_renders_notification_and_mouse_touch_dismiss_without_story_callback(self):
        self.lua.execute('''
            local notice={serial=4,to=3,food=1,water=2,coal=3};local dismissed=0;local originals=0
            local drawTexts={};require('game.typography').drawText=function(_,value)drawTexts[#drawTexts+1]=value end
            local g=setmetatable({getDimensions=function()return 960,720 end},{__index=function()return function()end end})
            love={graphics=g};local nextApp={draw=function()originals=originals+1 end,
                mousepressed=function()originals=originals+1 end,touchpressed=function()originals=originals+1 end}
            runtime.session={networkMode='host'};modal=false
            local ctx={controller=controller,ui={},runtime=runtime,screenToGame=function(x,y)return x,y end,
                commands={checkpointStatus=function()return{pending=false}end,
                    travelRequest=function()return notice end,
                    dismissTravelRequest=function(serial)assert(serial==4);dismissed=dismissed+1;notice=nil;return true end}}
            require('game.local_play_host').wrap(nextApp,ctx)
            nextApp.draw();assert(originals==1 and table.concat(drawTexts,'|'):find('Host decides.',1,true))
            nextApp.mousepressed(720,96,1,false);assert(dismissed==1 and originals==1)
            notice={serial=4,to=3,food=1,water=2,coal=3};nextApp.draw()
            nextApp.touchpressed('dismiss',720,96);assert(dismissed==2 and originals==2)
            assert(runtime.scene==nil and runtime.saveData==nil)
        ''')


class HostDepartureAfterRequestTests(unittest.TestCase):
    setUp=scene_tests.CoopSceneTests.setUp

    def test_only_real_host_departure_pays_commits_epoch_and_checkpoints_after_a_nonmutating_guest_request(self):
        self.lua.execute('''
            local Requests=require('game.coop_travel_requests');data.coop.revision=1
            local actor=context.actorState
            context.actorState=function(id)
                local state=actor(id)
                if id=='companion'then state.movementReady=true;state.motionId=3 end
                return state
            end
            Requests.install(service,context)
            local originalWrites=writes;local epoch=data.coop.sceneEpoch
            local resources=Schema.copy(data.resources)
            local inspection=assert(service:prepareRequest('companion','progression.request',{action='inspect',motionId=3}))
            local result=service:execute('companion',1,inspection);assert(result.ok,result.reason)
            local q={};for _,key in ipairs({'from','to','food','water','coal','sourceRevision'})do q[key]=result.result[key]end
            local req=assert(service:prepareRequest('companion','progression.request',{action='depart',motionId=3,quote=q}))
            assert(service:execute('companion',1,req).ok)
            assert(writes==originalWrites and data.resources.food==resources.food and data.coop.sceneEpoch==epoch and not data.coop.journey)
            local forbidden,reason=service:prepareRequest('companion','travel.depart',{})
            assert(not forbidden and reason=='host_only')
            local hostRequest=assert(service:prepareRequest('host','travel.depart',{}))
            local departure=service:execute('host',0,hostRequest);assert(departure.ok and departure.durable,departure.reason)
            assert(writes==originalWrites+1 and data.coop.sceneEpoch==epoch+1 and data.coop.journey.from==2 and data.coop.journey.to==3)
            assert(data.resources.food==resources.food-q.food and data.resources.water==resources.water-q.water and data.resources.coal==resources.coal-q.coal)
            assert(not Requests.notice(service,context));assert(service:execute('host',0,hostRequest).ok)
            assert(writes==originalWrites+1 and data.resources.coal==resources.coal-q.coal)
        ''')


if __name__=='__main__':unittest.main()
