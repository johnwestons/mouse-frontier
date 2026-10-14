"""Behavior guards for the natural adventure pilot; these do not launch LOVE."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class AdventureFixtureTests(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'tools/guest-adventure-smoke/main.lua').read_text(encoding='utf-8')
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().ADVENTURE_FIXTURE_HELPERS = True
        self.lua.globals().helpers = self.lua.execute(self.source)

    def test_entire_main_and_conf_parse_in_lua51(self):
        self.assertIsNotNone(self.lua.eval('loadstring')(self.source))
        self.assertIsNotNone(self.lua.eval('loadstring')((ROOT / 'tools/guest-adventure-smoke/conf.lua').read_text()))

    def test_pilot_routes_around_collision_wall_and_never_tunnels(self):
        self.lua.execute('''
            function walkable(x,y) return x>=6 and x<=954 and y>=6 and y<=714
                and not (x>=300 and x<=324 and y<=600) end
            assert(not helpers.segment(120,120,600,120,walkable))
            x,y=120,120;steps=0
            while (x-600)^2+(y-120)^2>1 do
                local nx,ny=helpers.route(x,y,600,120,walkable)
                assert(nx and helpers.segment(x,y,nx,ny,walkable))
                assert((nx-x)^2+(ny-y)^2>0)
                x,y=nx,ny;steps=steps+1;assert(steps<200)
            end
            assert(steps>2)
        ''')

    def test_disconnected_route_fails_instead_of_teleporting(self):
        self.lua.execute('''
            local x,y=helpers.route(120,120,600,120,function(x,y)
                return x>=6 and x<=954 and y>=6 and y<=714 and not(x>=300 and x<=324) end)
            assert(x==nil and y==nil)
        ''')

    def test_stall_timer_resets_on_real_progress_and_never_treats_subpixel_jitter_as_travel(self):
        self.lua.execute('''
            local p,t=helpers.progress(nil,'board-train',801,457,0);assert(t==0)
            p,t=helpers.progress(p,'board-train',801.1,457.1,3);assert(t==3)
            p,t=helpers.progress(p,'board-train',801.2,457.2,6);assert(t==6)
            p,t=helpers.progress(p,'board-train',795,461,6.1);assert(t==0)
            p,t=helpers.progress(p,'store-wait',795,461,8);assert(t==0)
        ''')

    def test_offer_pilot_recognizes_only_matching_unpaused_source_offer(self):
        self.lua.execute('''
            local q={lifecycle={mode='offer',entityId='e8',revision=4}}
            local d={lastStand=q};local s={mode='offer',capture=true,quest=q}
            assert(helpers.ordinaryOffer(d,s)=='e8:4')
            s.mode='shootout';assert(not helpers.ordinaryOffer(d,s));s.mode='offer'
            s.quest=helpers.copy(q);assert(not helpers.ordinaryOffer(d,s));s.quest=q
            s.paused=true;assert(not helpers.ordinaryOffer(d,s));s.paused=false
            s.pendingProgression={};assert(not helpers.ordinaryOffer(d,s));s.pendingProgression=nil
            q.lifecycle.mode='escort';assert(not helpers.ordinaryOffer(d,s))
        ''')

    def test_town_gate_requires_matching_host_decline_and_no_live_modal(self):
        self.lua.execute('''
            local q={state='waiting',lifecycle={mode='approach',entityId='e8',revision=4}}
            local d={scene='stop',location=6,lastStand=q};local r={scene='stop',state='game'}
            assert(not helpers.townReady(d,r,nil))
            q.state='declined';q.declinedStop=6
            assert(not helpers.townReady(d,r,nil))
            assert(not helpers.townReady(d,r,'e8:2') and not helpers.townReady(d,r,'e9:3'))
            assert(helpers.townReady(d,r,'e8:3'))
            q.declinedStop=5;assert(not helpers.townReady(d,r,'e8:3'));q.declinedStop=6
            q.lifecycle.mode='offer';assert(not helpers.townReady(d,r,'e8:3'));q.lifecycle.mode='approach'
            r.lastStand={capture=true};assert(not helpers.townReady(d,r,'e8:3'))
            r.lastStand={pendingProgression={}};assert(not helpers.townReady(d,r,'e8:3'))
            r.lastStand={capture=false};assert(helpers.townReady(d,r,'e8:3'))
            r.scene='expedition';assert(not helpers.townReady(d,r,'e8:3'));r.scene='stop'
            r.state='battle';assert(not helpers.townReady(d,r,'e8:3'))
        ''')

    def test_return_town_withholds_guest_trade_until_natural_offer_host_checkpoint_and_pause_clear(self):
        body = self.source.split('local function hostUpdate(lp)', 1)[1].split('local function guestUpdate(lp)', 1)[0]
        self.lua.execute('''
            Helpers=helpers;stage='return-town';markers={};now=10;stops=0
            c={runtime={state='game',scene='expedition',saveData={scene='expedition',location=6}},ui={},session={}}
            lp={network={link={phase='ready'}},authority={},pending=function()return nil end}
            love={timer={getTime=function()return now end}}
            WorldPause={isPaused=function()return paused==true end}
            function check(value,message)assert(value,message)end
            function file(name,value)if value~=nil then markers[name]=value end;return markers[name]end
            function battlePilot()return false end
            function walkTo(x,y,r)assert(x==836 and y==856 and r==55);return true end
            function stopWalk()stops=stops+1 end
            function interact()
                c.runtime.scene='stop'
                c.runtime.saveData={scene='stop',location=6,lastStand={state='waiting',lifecycle={mode='approach',entityId='e8',revision=4}}}
            end
        ''' + 'function hostUpdate(lp)' + body + '''
            hostUpdate(lp);assert(stage=='town-offer' and not markers['host.town'])
            hostUpdate(lp);assert(stops==1 and not markers['host.town'])
            local q=c.runtime.saveData.lastStand
            q.lifecycle.mode='offer';hostUpdate(lp);assert(not markers['host.town'])
            -- A canonical decline alone is insufficient while its actual save is withheld.
            q.state='declined';q.declinedStop=6;q.lifecycle.mode='approach';q.lifecycle.revision=5
            markers['host.offer.declined']='e8:4';c.session.checkpointPending=true
            hostUpdate(lp);assert(not markers['host.town'])
            c.session.checkpointPending=false;lp.authority.pendingSave={};hostUpdate(lp);assert(not markers['host.town'])
            lp.authority.pendingSave=nil;paused=true;hostUpdate(lp);assert(not markers['host.town'])
            paused=false;hostUpdate(lp);assert(stage=='trade-wait' and markers['host.town']=='e8:4')
        ''')

    def test_original_scout_approaches_stationary_host_and_opens_offer_without_forced_arrival(self):
        import test_coop_last_stand_source_behavior as source_tests
        harness = source_tests.LastStandSourceTests()
        harness.setUp()
        harness.lua.execute('''
            data=F.campaign(6);assert(F.enroll(data));data.scene='stop';data.stopped=true
            runtime.saveData=data;runtime.lastStand=nil;runtime.player={x=400,y=500,speed=185}
        ''')
        harness.story_authority()
        harness.lua.execute('''
            local sourcePositions={};local time=0
            for i=1,120 do
                sourceTick(.05);time=time+.05
                local state=runtime.lastStand;assert(state,'original scout did not start approach')
                if i==1 then
                    assert(state.mode=='approach' and not state.capture and state.arrival==0)
                    sourcePositions.x,sourcePositions.y=state.scout.x,state.scout.y
                end
                if state.mode=='offer' then break end
                assert(runtime.player.x==400 and runtime.player.y==500,'fixture moved host to manufacture arrival')
            end
            assert(runtime.lastStand.mode=='offer' and runtime.lastStand.capture and time>=2.8 and time<=6)
            assert(runtime.lastStand.scout.x~=sourcePositions.x and submitted('lastStand.offer')==1)
            assert(disk.lastStand.lifecycle.mode=='offer','natural offer was not checkpointed')
            assert(Source:keypressed('n'))
            assert(data.lastStand.state=='declined' and disk.lastStand.declinedStop==6)
            assert(not runtime.lastStand.capture)
        ''')

    def actual_offer_pilot(self, touch):
        import test_coop_last_stand_source_behavior as source_tests
        harness = source_tests.LastStandSourceTests()
        harness.setUp()
        harness.story_authority()
        self.lua = harness.lua
        self.lua.globals().ADVENTURE_FIXTURE_HELPERS = True
        self.lua.globals().helpers = self.lua.execute(self.source)
        self.lua.globals().touch = touch
        pilot = self.source.split('local function hostOfferPilot(lp)', 1)[1].split('local function hostUpdate(lp)', 1)[0]
        self.lua.execute('''
            Helpers=helpers;markers={};now=0;photos={};presses=0
            assert(Life.move(quest,'offer','waiting'));local originalRevision=quest.lifecycle.revision
            runtime.lastStand={mode='offer',capture=true,quest=quest,offerPage=1,arrival=1}
            c={runtime=runtime,session=runtime.session};lp={authority=story}
            Save={read=function() return disk end};love.timer={getTime=function() return now end}
            function check(value,message) assert(value,message) end
            function file(name,value) if value~=nil then markers[name]=value end;return markers[name] end
            function stopWalk() stopped=true end
            function photo(name,callback) photos[name]=callback end
            function button(key) presses=presses+1;assert(key=='n');return Source:keypressed(key) end
            function press(rect) presses=presses+1
                return Source:mousepressed(rect.x+rect.w/2,rect.y+rect.h/2,1,true,'real-touch') end
        ''' + 'function hostOfferPilot(lp)' + pilot + '''
            assert(hostOfferPilot(lp) and stopped and presses==0)
            assert(photos['host-adventure-last-stand-offer.png'] and quest.lifecycle.mode=='offer')
            markers['guest.offer.observed']=markers['host.offer.pending']
            assert(hostOfferPilot(lp) and presses==0) -- No decision before PNG callback.
            photos['host-adventure-last-stand-offer.png']()
            failStorySave=true
            assert(hostOfferPilot(lp) and presses==1 and runtime.session.checkpointPending)
            assert(quest.state=='declined' and quest.lifecycle.mode=='approach')
            assert(runtime.lastStand.mode=='offer' and runtime.lastStand.capture)
            assert(not markers['host.offer.declined'])
            assert(hostOfferPilot(lp) and presses==1) -- No repeated decision while save withheld.
            retryStory()
            assert(hostOfferPilot(lp) and markers['host.offer.declined'])
            assert(disk.lastStand.state=='declined' and disk.lastStand.lifecycle.revision==originalRevision+1)
            assert(not runtime.lastStand.capture and runtime.lastStand.mode=='approach')
            assert(not hostOfferPilot(lp) and presses==1)
        ''')

    def test_offer_actual_source_keyboard_decline_waits_for_durable_checkpoint(self):
        self.actual_offer_pilot(False)

    def test_offer_actual_source_touch_not_now_waits_for_durable_checkpoint(self):
        self.actual_offer_pilot(True)

    def test_actual_guest_offer_keys_cannot_accept_decline_or_emit_story_request(self):
        import test_coop_guest_last_stand_stage_behavior as guest_tests
        harness = guest_tests.GuestLastStandStageTests()
        harness.setUp()
        harness.passive('offer')
        harness.lua.execute('''
            controller.network.nextRequestId=77
            controller.network.submitCommand=function() error('guest emitted offer command') end
            local life=view.runtime.saveData.lastStand.lifecycle
            local revision=life.revision
            assert(view.lastStand:available())
            assert(view:keypressed('n'));assert(view:keypressed('y'))
            assert(life.mode=='offer' and life.revision==revision and not parent.pending)
            assert(controller.network.nextRequestId==77 and not controller.network.pendingCommand)
            assert(require('game.net.codec').encode(data,{maxBytes=32768,maxDepth=16,maxEntries=2048})==before)
        ''')

    def test_actual_stop6_mask_and_source_botanist_physics_have_reachable_return_path(self):
        from PIL import Image
        self.lua.globals().root = ROOT.as_posix()
        pixels = Image.open(ROOT / 'assets/sprites/stops/walkmask-06.png').convert('RGB')
        mask = self.lua.table()
        mask.getDimensions = lambda *args: pixels.size
        mask.getPixel = lambda _, x, y: tuple(v / 255 for v in pixels.getpixel((int(x), int(y)))) + (1,)
        self.lua.globals().mask = mask
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            local S=require('game.settlements');S.walkMasks={[6]=mask}
            local M=require('game.character_motion');local profile=M.profileFor('botanist-frog.png')
            local ax,ay=S.clamp(S.trainPoint(6));local x,y=S.trainPoint(6)
            ax,ay=S.clamp(x,y,6)
            local actor={x=871.34743142595,y=415.23987995825,animationDistance=0}
            local nav;local time=0;local arrived=false
            for frame=1,600 do
                time=time+1/60
                if not nav or time-nav.at>.4 or (actor.x-nav.x)^2+(actor.y-nav.y)^2<64 then
                    local nx,ny=helpers.route(actor.x,actor.y,ax,ay,function(x,y)return S.isWalkable(6,x,y)end)
                    assert(nx);nav={x=nx,y=ny,at=time}
                end
                local dx,dy=nav.x-actor.x,nav.y-actor.y;local length=math.max(1,math.sqrt(dx*dx+dy*dy))
                dx,dy=dx/length,dy/length
                local mx=dx>.16 and 1 or dx<-.16 and -1 or 0
                local my=dy>.16 and 1 or dy<-.16 and -1 or 0
                M.updateActor(actor,mx,my,1/60,{profile=profile,speed=185,
                    move=function(a,b,x,y)return S.move(6,a,b,x,y)end})
                assert(S.isWalkable(6,actor.x,actor.y))
                if (actor.x-ax)^2+(actor.y-ay)^2<=14^2 then arrived=true;break end
            end
            assert(arrived and S.nearTrain(actor.x,actor.y,6))
        ''')

    def test_durable_receipt_requires_matching_request_and_arrived_projection(self):
        self.lua.execute('''
            local r={requestId=8,ok=true,durable=false,revision=11}
            assert(not helpers.readyReceipt(r,8,11));r.durable=true
            assert(not helpers.readyReceipt(r,9,11))
            assert(not helpers.readyReceipt(r,8,10))
            assert(helpers.readyReceipt(r,8,11));r.ok=false
            assert(not helpers.readyReceipt(r,8,100))
        ''')

    def test_real_prediction_can_show_cache_in_range_while_original_authority_rejects_checked_actor(self):
        from PIL import Image
        import test_coop_expedition_assistance_behavior as assistance_tests
        harness = assistance_tests.ExpeditionAssistanceTests()
        harness.setUp()
        harness.expedition()
        lua = harness.lua
        lua.globals().ADVENTURE_FIXTURE_HELPERS = True
        lua.globals().helpers = lua.execute(self.source)
        pixels = Image.open(ROOT / 'assets/sprites/expeditions/stop06/walkmask-outskirts.png').convert('RGB')
        mask = lua.table()
        mask.getDimensions = lambda *args: pixels.size
        mask.getPixel = lambda _, x, y: tuple(v / 255 for v in pixels.getpixel((int(x), int(y)))) + (1,)
        lua.globals().cacheMask = mask
        lua.execute('''
            love.image={newImageData=function()return cacheMask end}
            data.location=6;data.scene='expedition';data.activeExpeditionArea=Areas.SURFACE_ID
            Areas.ensure(data);assert(Entities.ensure(data));area=data.expeditions[Areas.SURFACE_ID]
            local targetX,targetY=1520,467;local x,y
            for sector=0,35 do
                local angle=sector*math.pi/18
                local ax,ay=targetX+70*math.cos(angle),targetY+70*math.sin(angle)
                if Areas.isWalkable(data,Areas.SURFACE_ID,ax,ay,true)
                    and Areas.canReach(data,Areas.SURFACE_ID,ax,ay,targetX,targetY,true)then x,y=ax,ay;break end
            end
            assert(x,'actual authored cache mask has no reachable 70px approach')
            states.companion.x,states.companion.y=x,y
            local now=0;local Wire=require('game.net.movement');local Protocol=require('game.net.protocol')
            local Predictor=require('game.coop_prediction')
            local predictor=Predictor.new({clock=function()return now end,data=function()return data end,
                move=function(_,_,ox,oy,nx,ny)return Areas.move(data,Areas.SURFACE_ID,ox,oy,nx,ny,true)end})
            local checked={x=x,y=y,facing=1,activeCar=1,character=data.players.companion.character}
            local hostPose={x=836,y=842,facing=1,activeCar=1,character=data.players.host.character}
            local function frame(serial,pose)
                return Protocol.message('motion',{sessionId='reach-fixture',motionId=1,sceneEpoch=data.coop.sceneEpoch,
                    serial=serial,tick=serial,ack=0,ackAge=0,inputActive=false,paused=false,ready=true,
                    host=Wire.packActor(hostPose,data.players.host),companion=Wire.packActor(pose,data.players.companion)})
            end
            predictor:reset(data.coop.sceneEpoch,checked,hostPose,1);local baseline=frame(1,checked)
            assert(predictor:receive(baseline,true))
            local input={x=(targetX-x)/70,y=(targetY-y)/70,sprint=false};assert(predictor:sent(1,input))
            for step=1,15 do now=step/60;assert(predictor:update(input,true))end
            local predicted=predictor.display
            assert((predicted.x-targetX)^2+(predicted.y-targetY)^2<=50^2,'legal prediction did not enter old pilot arrival radius')
            assert(Assist.nearest(data,{scene='expedition',x=predicted.x,y=predicted.y}).chestId=='surface-cache')
            local view={ready=true,epoch=data.coop.sceneEpoch,motionId=1,lastSerial=1,modalDomain=nil,
                runtime={scene='expedition',saveData=data,player=predicted}}
            local lp={network={status='ready',sessionId='reach-fixture'},clientView=view,replica={data=data},motionFrame=baseline}
            assert(helpers.motionReady(lp) and not helpers.guestArrival(lp,targetX,targetY,50,Areas))
            local chest=area.chests['surface-cache'];local before=Schema.copy(data)
            local rejected=cache('companion',chest)
            assert(not rejected.ok and rejected.reason=='out_of_reach' and writes==0 and not chest.opened)
            assert(helpers.same(data,before,false),'rejected reach changed campaign state')
            -- A later checked snapshot can prove actual arrival. No fixture
            -- actor position is ever submitted as part of the cache request.
            local arrived=frame(2,predicted);lp.motionFrame=arrived;view.lastSerial=2
            assert(helpers.guestArrival(lp,targetX,targetY,50,Areas))
            states.companion.x,states.companion.y=predicted.x,predicted.y
            local accepted=cache('companion',chest)
            assert(accepted.ok and accepted.durable and writes==1 and chest.opened)
        ''')

    def test_checked_arrival_rejects_unpresented_motion_and_requires_read_only_reach(self):
        import test_coop_guest_view_behavior as guest_tests
        harness = guest_tests.GuestViewTests()
        harness.setUp()
        lua = harness.lua
        lua.globals().ADVENTURE_FIXTURE_HELPERS = True
        lua.globals().helpers = lua.execute(self.source)
        lua.execute('''
            ready();controller.clientView=view;controller.network.status='ready';controller.network.sessionId='guest-test'
            local f=controller.motionFrame;f.companion.x=1510000;f.companion.y=467000
            view.runtime.player.x,view.runtime.player.y=1510,467
            data.scene='expedition';data.activeExpeditionArea='stop06-outskirts'
            view.runtime.scene='expedition';view.runtime.saveData.scene='expedition';view.runtime.saveData.activeExpeditionArea=data.activeExpeditionArea
            local calls=0;local reachable=false
            local areas={canReach=function(d,id,x,y,tx,ty,readOnly)
                calls=calls+1;assert(d==view.runtime.saveData and id==data.activeExpeditionArea)
                assert(x==1510 and y==467 and tx==1520 and ty==467 and readOnly==true);return reachable
            end}
            assert(not helpers.guestArrival(controller,1520,467,50,areas) and calls==1)
            reachable=true;assert(helpers.guestArrival(controller,1520,467,50,areas) and calls==2)
            view.lastSerial=f.serial-1;assert(not helpers.guestArrival(controller,1520,467,50,areas) and calls==2)
            view.lastSerial=f.serial;f.companion.x=1450000
            assert(not helpers.guestArrival(controller,1520,467,50,areas) and calls==2)
            f.companion.x=1510000;view.runtime.player.x=1400
            assert(not helpers.guestArrival(controller,1520,467,50,areas) and calls==2)
        ''')

    def test_paced_cache_and_battle_controls_fit_actual_ordinary_command_budget(self):
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            local rate=require('game.net.command_rate');local link={}
            local actions={'expedition.interact','inventory.transfer','inventory.transfer',
                'inventory.transfer','inventory.consume','battle.selectWeapon','battle.attack',
                'battle.move','battle.endTurn','merchant.buy','inventory.transfer','inventory.transfer'}
            for i,name in ipairs(actions) do
                local now=(i-1)*helpers.ACTION_INTERVAL
                assert(helpers.actionReady(now+.000001,now-helpers.ACTION_INTERVAL))
                assert(not helpers.actionReady(now+.59,now))
                assert(rate.allow(link,{command=name,args={}},now),name..' exhausted production budget')
            end
            local burst={}
            for i=1,4 do assert(rate.allow(burst,{command=actions[i],args={}},0)) end
            assert(not rate.allow(burst,{command=actions[5],args={}},0))
            assert(rate.allow(burst,{command=actions[5],args={}},helpers.ACTION_INTERVAL))
        ''')

    def test_real_source_mobile_checkpoint_cancels_finger_and_pilot_represses_only_after_ready(self):
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={system={getOS=function() return 'Android' end},
                graphics={getDimensions=function() return 1120,840 end},timer={getTime=function() return 1 end}}
            local V=require('game.viewport');local S=require('game.ui_layout')
            local runtime={state='game',scene='expedition',saveData={},player={x=836,y=842},
                session={networkMode='host',checkpointPending=false}}
            local ui={};local input={keypressed=function() end,keyreleased=function() end,
                mousepressed=function() return false end,mousemoved=function() end,mousereleased=function() end,
                beginTouchPickup=function() return false end}
            local mobile=require('game.mobile_runtime').new({runtime=runtime,ui=ui,maintenanceSession={},
                mobileControls=require('game.mobile_controls'),width=960,height=720,
                viewportToGame=function(x,y)return V.toGame(x,y,960,720)end,
                getCameraZoom=function()return 1 end,setCameraZoom=function() end,
                beginCameraPan=function()end,moveCameraPan=function()end,endCameraPan=function()end,
                getGameplayInput=function()return input end})
            local controls=mobile.initialize();local presses,releases=0,0
            local app={update=function()end,draw=function()end,keypressed=input.keypressed,keyreleased=input.keyreleased,
                touchpressed=function(...)presses=presses+1;return mobile.touchpressed(...)end,
                touchmoved=mobile.touchmoved,touchreleased=function(...)releases=releases+1;return mobile.touchreleased(...)end}
            local commands={checkpointStatus=function()return {pending=runtime.session.checkpointPending}end,
                suspendActivities=function()end,retryCheckpoint=function()runtime.session.checkpointPending=false;return true end}
            require('game.coop_checkpoint_host').wrap(app,{runtime=runtime,ui=ui,commands=commands,
                audio={update=function()end},neutralize=function()mobile.focus(false)end,requestQuit=function()end})
            function point(x,y)
                local p=S.transformRectFor('mobileControls',controls:uiBounds(),{x=x,y=y,w=0,h=0})
                local ox,oy,sx,sy=V.transform(960,720);return ox+p.x*sx,oy+p.y*sy
            end
            local held,t=helpers.driveTouch(controls,false,app.touchpressed,app.touchmoved,app.touchreleased,point,1,0)
            assert(held and controls.touches['adventure-walk'].kind=='joystick' and presses==1)
            assert(controls:movement()>.9)
            runtime.session.checkpointPending=true;app.update(.016)
            assert(not controls.touches['adventure-walk'] and controls:movement()==0)
            held,t=helpers.driveTouch(controls,held,app.touchpressed,app.touchmoved,app.touchreleased,point,1,0)
            assert(not held and t.recovered and not t.movementActive and presses==1)
            app.keypressed('r');assert(not runtime.session.checkpointPending)
            local x,y=point(controls.joystick.x+controls.joystick.radius*.95,controls.joystick.y)
            assert(not mobile.touchmoved('adventure-walk',x,y,0,0) and controls:movement()==0,
                'old pilot moved an unowned finger after cancellation')
            -- Even a stale pilot flag is repaired with an actual release and new press.
            held,t=helpers.driveTouch(controls,true,app.touchpressed,app.touchmoved,app.touchreleased,point,1,0)
            assert(held and t.recovered and t.movementActive and presses==2 and releases>=1)
            assert(controls:movement()>.9 and controls.joystickTouch=='adventure-walk')
            assert(runtime.player.x==836 and runtime.player.y==842) -- No pilot positioning or keyboard bypass.
        ''')

    def test_restart_rejects_old_ready_and_unacknowledged_new_link(self):
        self.lua.execute('''
            assert(not helpers.newSession({status='ready',sessionId='old'},'old','new'))
            assert(not helpers.newSession({status='snapshot',sessionId='new'},'old','new'))
            assert(not helpers.newSession({status='ready',sessionId='other'},'old','new'))
            assert(helpers.newSession({status='ready',sessionId='new'},'old','new'))
        ''')

    def test_actual_join_and_rejoin_close_menu_before_waiting_for_fresh_motion(self):
        ready = self.source.split('local function ready()', 1)[1].split('local function ownItem(', 1)[0]
        guest = self.source.split('local function guestUpdate(lp)', 1)[1].split('local function update(dt)', 1)[0]
        self.lua.execute('''
            Helpers=helpers;markers={};closed=0
            function file(name,value) if value~=nil then markers[name]=value end;return markers[name] end
            lp={menuOpen=true,network={status='ready',sessionId='first',campaignId='campaign',credential={companionId='friend'}},
                replica={data={scene='train',location=6,coop={sceneEpoch=8}}},
                motionFrame={ready=false,paused=false,sceneEpoch=8,motionId=5,serial=3,sessionId='first'}}
            view={ready=true,epoch=8,motionId=5,lastSerial=3,runtime={scene='train',
                saveData={scene='train',location=6,coop={sceneEpoch=8},resources={food=10},
                    itemSlots={equipment={[2]={id='original-sling',name='trail-slingshot'}}}}}}
            function view:actionsAllowed() return not lp.menuOpen and lp.motionFrame.ready end
            lp.clientView=view;c={ui={localPlay=lp}}
            function back() assert(lp.menuOpen);closed=closed+1;lp.menuOpen=false end
            function menu() lp.menuOpen=true end
            function click(id) lastControl=id end
            function completeRequest() return true end
            function samePublic() compared=true end
            function ownIdentity() return 2,{id='purchase'} end
            function ownItem() return 2 end
            function check(v,m) assert(v,m) end
            function photo(name,fn) captured=name;callback=fn end
        ''' + 'function ready()' + ready + 'function guestUpdate(lp)' + guest)
        self.lua.execute('''
            stage='joining';guestUpdate(lp)
            assert(closed==1 and not lp.menuOpen and stage=='joining' and not markers['guest.initial.ready'])
            guestUpdate(lp);assert(stage=='joining')
            lp.motionFrame.ready=true;guestUpdate(lp)
            assert(stage=='wait-stop' and markers['guest.initial.ready'] and initialCampaign=='campaign' and initialCompanion=='friend')
            stage='restart-wait';oldSession='first';markers['host.resumed.session']='second'
            lp.menuOpen=true;guestUpdate(lp);assert(closed==1 and not captured) -- Old ready link is never accepted.
            lp.network.sessionId='second';lp.motionFrame.ready=false;guestUpdate(lp)
            assert(closed==2 and stage=='restart-wait' and not captured)
            guestUpdate(lp);assert(not captured and not compared)
            lp.motionFrame.ready=true;lp.motionFrame.sessionId='second';guestUpdate(lp)
            assert(compared and captured=='guest-adventure-reloaded.png' and stage=='restart-wait')
            callback();assert(stage=='take-reloaded')
        ''')

    def test_scene_readiness_rejects_old_scene_epoch_domain_or_unpresented_motion(self):
        self.lua.execute('''
            local data={scene='stop',location=6,coop={sceneEpoch=8}}
            local lp={network={status='ready',sessionId='session'},replica={data=data},
                clientView={ready=true,epoch=8,motionId=5,lastSerial=3,
                    runtime={scene='stop',saveData=helpers.copy(data)}},
                motionFrame={ready=true,paused=false,sceneEpoch=8,motionId=5,serial=3,sessionId='session'}}
            assert(helpers.motionReady(lp))
            lp.replica.data={scene='expedition',location=6,activeExpeditionArea='stop06-outskirts',coop={sceneEpoch=9}}
            assert(not helpers.reliableView(lp)) -- Reliable new scene arrived before its presented view.
            lp.clientView.epoch=9;lp.clientView.runtime.saveData=helpers.copy(lp.replica.data)
            assert(not helpers.reliableView(lp)) -- Runtime still presents Stop.
            lp.clientView.runtime.scene='expedition';assert(helpers.reliableView(lp))
            assert(not helpers.motionReady(lp)) -- Old ready motion cannot move the new expedition actor.
            lp.motionFrame.sceneEpoch=9;lp.motionFrame.motionId=6
            assert(not helpers.motionReady(lp)) -- New motion not presented yet.
            lp.clientView.motionId=6;assert(helpers.motionReady(lp))
            lp.motionFrame.serial=4;assert(not helpers.motionReady(lp))
            lp.clientView.lastSerial=4;assert(helpers.motionReady(lp))
            lp.motionFrame.domain='old-modal';assert(not helpers.motionReady(lp))
            lp.motionFrame.domain=nil;lp.motionFrame.sessionId='old-session';assert(not helpers.motionReady(lp))
        ''')

    def test_actual_expedition_mask_waypoint_is_read_only_on_production_projection(self):
        from PIL import Image
        self.lua.globals().root = ROOT.as_posix()
        masks = {}
        def load_mask(path):
            if path not in masks:
                pixels = Image.open(ROOT / path).convert('RGB')
                mask = self.lua.table()
                mask.getDimensions = lambda *args: pixels.size
                mask.getPixel = lambda _, x, y: tuple(value / 255 for value in pixels.getpixel((int(x), int(y)))) + (1,)
                masks[path] = mask
            return masks[path]
        self.lua.globals().loadMask = load_mask
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random},image={newImageData=loadMask}}
            local F=require('tools.tests.lua.coop_fixtures');local Areas=require('game.expedition_areas')
            local campaign=F.campaign(6,{scene='expedition',activeExpeditionArea=Areas.SURFACE_ID})
            assert(F.enroll(campaign));Areas.ensure(campaign)
            assert(require('game.item_instances').ensure(campaign))
            local projection=assert(require('game.net.game_state').project(campaign)).view
            assert(not projection.coop.nextEntityId and not projection.itemIdentity)
            local before=helpers.copy(projection)
            local readonly={definition=Areas.definition,isWalkable=function(data,id,x,y,flag)
                assert(flag==true and data==projection);return Areas.isWalkable(data,id,x,y,flag) end}
            local x,y=helpers.guestAreaWaypoint(projection,Areas.SURFACE_ID,836,842,1520,467,readonly)
            assert(x and y and Areas.isWalkable(projection,Areas.SURFACE_ID,x,y,true))
            assert(helpers.segment(836,842,x,y,function(px,py) return Areas.isWalkable(projection,Areas.SURFACE_ID,px,py,true) end))
            assert(helpers.same(projection,before,false))
            assert(not projection.coop.nextEntityId and not projection.itemIdentity)
        ''')

    def test_actual_touch_interact_uses_stop_primary_and_expedition_secondary(self):
        body = self.source.split('local function interact()', 1)[1].split('local function bagPress(', 1)[0]
        self.lua.execute('''
            Helpers=helpers;touch=true;role='host';scene='stop'
            controls={primary={x=100,y=200},secondary={x=300,y=400},uiBounds=function() return {} end}
            c={getMobileControls=function() return controls end,ui={localPlay={clientView={mobile=controls}}}}
            app={draw=function() end};Style={transformRectFor=function(_,_,r) return r end}
            function runtime() return {scene=scene} end
            function stopWalk() stopped=true end
            function press(r) point=r end
        ''' + 'function interact()' + body)
        self.lua.execute('''
            interact();assert(stopped and point.x==100 and point.y==200)
            scene='expedition';interact();assert(point.x==300 and point.y==400)
            role='guest';interact();assert(point.x==100 and point.y==200)
            scene='train';interact();assert(point.x==100 and point.y==200)
        ''')

    def test_host_return_walks_to_real_train_anchor_and_requires_contextual_board(self):
        self.lua.globals().root = ROOT.as_posix()
        body = self.source.split('local function hostUpdate(lp)', 1)[1].split('local function guestUpdate(lp)', 1)[0]
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Settlements=require('game.settlements');Router=require('game.interaction_router')
            stage='board-train';touch=false;arrived=false;inputs=0;markers={};captures={['host-train-approach.png']=true}
            c={runtime={state='game',scene='stop',player={x=871,y=415},saveData={scene='stop',location=6}},
                ui={interaction={kind='returnTrain'}},session={checkpointPending=false}}
            lp={network={link={phase='ready'}},pending=function() return nil end}
            app={draw=function() end}
            function check(v,m) assert(v,m) end
            function battlePilot() return false end
            function walkTo(x,y,radius)
                local tx,ty=Settlements.trainPoint(6)
                local ax,ay=Settlements.clamp(tx,ty,6)
                assert(x==ax and y==ay and radius==14)
                if arrived then c.runtime.player.x,c.runtime.player.y=x,y end;return arrived
            end
            function file(name,value) markers[name]=value;return value end
            function interact()
                assert(Router.keyAction({selected=c.ui.interaction},'e')=='returnTrain')
                inputs=inputs+1;c.runtime.scene='train'
                -- A real transition may replace the runtime campaign reference.
                c.runtime.saveData={scene='train',location=6}
            end
        ''' + 'function hostUpdate(lp)' + body)
        self.lua.execute('''
            hostUpdate(lp);assert(inputs==0 and stage=='board-train')
            arrived=true;c.ui.interaction={kind='npc'}
            assert(not pcall(hostUpdate,lp) and inputs==0)
            c.ui.interaction={kind='returnTrain'};hostUpdate(lp)
            assert(inputs==1 and stage=='store-wait' and markers['host.train']=='true')
        ''')

    def test_inventory_purchase_proof_rejects_old_loot_wrong_item_and_other_deliveries(self):
        self.lua.execute('''
            local before=helpers.identities({[1]={id='water',name='water-bottle'},[4]={id='battle-loot',name='rusty-cleaver'}})
            local after={[1]={id='water',name='water-bottle'},[4]={id='battle-loot',name='rusty-cleaver'}}
            local detail={delivery='inventory',item='food-ration'}
            assert(not helpers.purchasedIdentity(before,after,detail)) -- Existing battle loot cannot masquerade as a buy.
            after[2]={id='new-item',name='food-ration'}
            assert(helpers.purchasedIdentity(before,after,detail)=='new-item')
            detail.delivery='ammo';assert(not helpers.purchasedIdentity(before,after,detail))
            detail.delivery='train';assert(not helpers.purchasedIdentity(before,after,detail))
            detail.delivery='inventory';detail.item='water-bottle'
            assert(not helpers.purchasedIdentity(before,after,detail))
            detail.item='food-ration';after[3]={id='another-new-item',name='food-ration'}
            assert(not helpers.purchasedIdentity(before,after,detail))
            after[3]=nil;after[4]=nil;assert(not helpers.purchasedIdentity(before,after,detail))
        ''')

    def test_purchase_proof_distinguishes_unidentified_supplies_from_identified_gear(self):
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            local Items=require('game.item_instances')
            local names={[1]='water-bottle',[3]='field-bandage-roll',[4]='frontier-short-sword'}
            local records={[4]={id='old-sword',name='frontier-short-sword'}}
            local oldNames=helpers.copy(names);local ids=helpers.identities(records)
            names[2]='thread-spool'
            local slot,id=helpers.purchasedSlot(oldNames,ids,names,records,{delivery='inventory',item='thread-spool'},Items.isGear)
            assert(slot==2 and id==false)
            names[2]=nil;assert(not helpers.purchasedSlot(oldNames,ids,names,records,{delivery='inventory',item='thread-spool'},Items.isGear))
            names[2]='frontier-short-sword'
            assert(not helpers.purchasedSlot(oldNames,ids,names,records,{delivery='inventory',item='frontier-short-sword'},Items.isGear))
            records[2]={id='new-sword',name='frontier-short-sword'}
            slot,id=helpers.purchasedSlot(oldNames,ids,names,records,{delivery='inventory',item='frontier-short-sword'},Items.isGear)
            assert(slot==2 and id=='new-sword')
        ''')

    def test_actual_cache_consumables_transfer_without_compaction_or_invented_identity_and_real_weapon_roundtrips(self):
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            local F=require('tools.tests.lua.coop_fixtures');local Items=require('game.item_instances')
            local Areas=require('game.expedition_areas');local Players=require('game.coop_players')
            local Inventory=require('game.inventory');local C=require('game.catalog');local Contract=require('game.coop_item_contract')
            local campaign=F.campaign(6);assert(F.enroll(campaign));Areas.ensure(campaign);assert(Items.ensure(campaign))
            local own=Players.forActor(campaign,'companion');local cache=campaign.expeditions[Areas.SURFACE_ID].chests['surface-cache']
            local selected=Contract.selection(own,cache,{kind='chest',index=2})
            assert(selected.name=='water-bottle' and selected.id==false)
            assert(Inventory.quickTransfer(own,cache,{kind='chest',index=2},C.weaponStats,C.ammoPickupAmounts,C.storageCapacities,C.wearableItems))
            assert(own.inventory[1]=='water-bottle' and own.itemSlots.inventory[1]==nil)
            assert(cache.storage[1]=='food-ration' and cache.storage[2]==nil and cache.storage[3]=='field-bandage-roll')
            assert(not Items.isGear('water-bottle') and not Items.isGear('food-ration') and not Items.isGear('field-bandage-roll'))
            own.itemSlots.equipment[2].durability=73
            local record=helpers.copy(own.itemSlots.equipment[2]);local ammo=helpers.copy(own.ammo)
            local chest={name='travel-chest',scene='train',carIndex=1,x=400,y=400,storage={},storageInstances={}}
            campaign.droppedItems[#campaign.droppedItems+1]=chest
            assert(require('game.coop_entities').ensure(campaign));assert(Items.ensure(campaign))
            assert(Inventory.quickTransfer(own,chest,{kind='equipment',index=2},C.weaponStats,C.ammoPickupAmounts,C.storageCapacities,C.wearableItems))
            assert(own.equipment[2]==nil and own.itemSlots.equipment[2]==nil and helpers.same(chest.storageInstances[1],record,false))
            local fs=F.filesystem();love.filesystem=fs;local Save=require('game.save')
            assert(Save.write(1,campaign));local disk=assert(Save.read(1))
            local restored=disk.droppedItems[#disk.droppedItems]
            assert(helpers.same(restored.storageInstances[1],record,false))
            own=Players.forActor(disk,'companion');chest=restored
            assert(Inventory.quickTransfer(own,chest,{kind='chest',index=1},C.weaponStats,C.ammoPickupAmounts,C.storageCapacities,C.wearableItems))
            assert(helpers.same(own.itemSlots.inventory[2],record,false) and helpers.same(own.ammo,ammo,false))
            assert(not next(chest.storage) and not next(chest.storageInstances))
        ''')

    def test_sparse_exact_item_records_encode_and_only_disk_float_rounding_is_tolerated(self):
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            local codec=require('game.net.codec')
            local sparse=helpers.record({inventory={[2]={id='same-item'},[6]={id='other-item'}},position=1.23456789012345})
            assert(codec.encode(sparse));assert(sparse.inventory['2'].id=='same-item')
            local disk=helpers.copy(sparse);disk.position=1.2345678901234
            assert(not helpers.same(sparse,disk,false));assert(helpers.same(sparse,disk,true))
            disk.inventory['2'].id='replacement';assert(not helpers.same(sparse,disk,true))
            disk=helpers.copy(sparse);disk.ammo=12;sparse.ammo=11
            assert(not helpers.same(sparse,disk,true))
        ''')

    def test_screenshot_stage_change_waits_for_actual_png_callback(self):
        body = self.source.split('local function draw()', 1)[1].split('local function guarded(', 1)[0]
        self.lua.execute('''
            app={draw=function() draws=(draws or 0)+1 end};finished=false
            stage='before';capture='actual.png';captures={}
            afterCapture=function() stage='after' end
            love={graphics={captureScreenshot=function(fn) queued=fn end}}
            function encode(self,kind,name) assert(kind=='png' and name=='actual.png');encoded=true end
        ''' + 'function draw()' + body)
        self.lua.execute('''
            draw();assert(stage=='before' and capturePending and queued and not encoded)
            assert(not helpers.captureReady(capture,capturePending))
            queued({encode=encode});assert(encoded and stage=='after' and captures['actual.png'])
            assert(helpers.captureReady(capture,capturePending))
        ''')

    def test_signature_handles_actual_production_replica_without_private_network_or_rng(self):
        self.lua.globals().root = ROOT.as_posix()
        body = self.source.split('local function travelChest(d)', 1)[1].split('local function hostControl(', 1)[0]
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            Helpers=helpers;Codec=require('game.net.codec');Areas=require('game.expedition_areas')
            function check(value,message) assert(value,message) end
            F=require('tools.tests.lua.coop_fixtures');State=require('game.net.game_state')
            campaign=F.campaign(6,{scene='train',droppedItems={{name='travel-chest',scene='train',carIndex=1,x=400,y=400,storage={}}}})
            assert(F.enroll(campaign));Areas.ensure(campaign)
            assert(require('game.coop_entities').ensure(campaign));assert(require('game.item_instances').ensure(campaign))
            campaign.coop.network={version=1,campaignId=string.rep('a',32),companionId=string.rep('b',32),
                credentialHash=string.rep('c',64),bindingVersion=1}
            campaign.coop.randomState=345678
        ''' + 'local function travelChest(d)' + body + '''
            local projected=assert(State.project(campaign)).view
            assert(not projected.coop.network and not projected.coop.randomState)
            local pub=publicSignature(campaign);samePublic(projected,pub,'projected facts',false)
            projected.players.companion.inventory[1]='untracked-supply'
            assert(not pcall(samePublic,projected,pub,'changed supplies',true));projected.players.companion.inventory[1]=nil
            local private=signature(campaign);sameSignature(campaign,private,'original facts',false)
            campaign.coop.randomState=345679;assert(not pcall(sameSignature,campaign,private,'changed RNG',true))
            campaign.coop.randomState=345678
            projected.players.companion.itemSlots.equipment[1].id='replacement'
            assert(not pcall(samePublic,projected,pub,'replaced owned item',true))
        ''')

    def test_initial_seed_search_uses_real_stop_rules_and_retains_original_owned_gear(self):
        self.lua.globals().root = ROOT.as_posix()
        body = self.source.split('local function generatedInitial()', 1)[1].split('local function load()', 1)[0]
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}; Helpers=helpers
            Stops=require('game.stops');Random=require('game.coop_random')
            Players=require('game.coop_players');Items=require('game.item_instances');Schema=require('game.save_schema')
            function check(value,message) assert(value,message) end
            local F=require('tools.tests.lua.coop_fixtures')
            original=F.campaign(1,{scene='train',npcRoster={'cook-mouse.png','crow-merchant.png','scout-frog.png'}})
            c={characters={'scout-frog.png'},catalog=require('game.catalog'),newSave=function() return helpers.copy(original) end}
        ''' + 'function generatedInitial()' + body + '''
            local seed=generatedInitial()
            assert(seed.location==6 and seed.events['6'].id=='resolved' and seed.encounters['6'].resolved)
            assert(seed.stopLayouts['6'].npcOutside=='crow-merchant.png')
            assert(seed.stopLayouts['6'].npcOffers['crow-merchant.png']=='trade')
            assert(Schema.validate(seed));assert(Schema.migrate(seed))
            assert(seed.stopLayouts['6'].npcWeaponInstance and seed.stopLayouts['6'].entityId)
            assert(helpers.same(seed.players.host.itemSlots,original.players.host.itemSlots,false),'seed replaced owned gear')
            assert(helpers.same(seed.players.host.ammo,original.players.host.ammo,false),'seed changed ammo')
            assert(seed.players.host.health==original.players.host.health and seed.scrap==original.scrap,'seed changed health/scrap')
            assert(original.location==1 and not original.stopLayouts['6'])
        ''')

    def test_normal_generated_npc_requires_identity_preparation_before_canonical_load(self):
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            local F=require('tools.tests.lua.coop_fixtures');local Items=require('game.item_instances')
            local Schema=require('game.save_schema');local Random=require('game.coop_random')
            local campaign=F.campaign(6,{npcRoster={'crow-merchant.png'}})
            local gear=helpers.copy(campaign.players.host.itemSlots);local ammo=helpers.copy(campaign.players.host.ammo)
            local health=campaign.players.host.health
            require('game.stops').ensure(campaign,require('game.catalog'),'stop',Random.generator(campaign,45))
            local loaded,why=Schema.migrate(campaign)
            assert(not loaded and why=='missing item identity')
            assert(require('game.coop_entities').ensure(campaign));assert(Items.ensure(campaign))
            assert(Schema.validate(campaign));assert(Schema.migrate(campaign))
            assert(campaign.stopLayouts['6'].npcWeaponInstance)
            assert(helpers.same(gear,campaign.players.host.itemSlots,false))
            assert(helpers.same(ammo,campaign.players.host.ammo,false) and campaign.players.host.health==health)
        ''')

    def battle_pilot(self):
        self.lua.globals().root = ROOT.as_posix()
        body = self.source.split('local function battlePilot()', 1)[1].split('local function finish()', 1)[0]
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random},timer={getTime=function() return 10 end}}
            Rules=require('game.battle_rules');Weapons=require('game.battle_weapon_ownership')
            Actors=require('game.battle_actors');catalog=require('game.catalog')
            local F=require('tools.tests.lua.coop_fixtures');campaign=F.campaign(6);assert(F.enroll(campaign))
            unit={id='player',actorId='host',team='ally',hp=17,q=1,r=1,move=3}
            enemy={id='mob',team='enemy',hp=18,q=2,r=1}
            battle={units={unit,enemy},active=1,phase='select',tiles={}}
            for q=0,9 do battle.tiles[q]={};for r=1,6 do battle.tiles[q][r]=1 end end
            campaign.tacticalBattle={encounterId='battle-test'}
            c={catalog=catalog,ui={battleWeapons={{id='scratch'},{id='sword'},{id='sling'}},
                battleMove={id='move'},battleEnd={id='end'}},uiUnused={},runtime={saveData=campaign,battle=battle},
                uiPlaceholder={}}
            c.ui.localPlay={authority={pendingSave=false}}
            role='host';battleId='battle-test';hostAttacks=0;lastAction=0
            function runtime() return c.runtime end;function data() return campaign end
            function stopWalk() stopped=true end;function check(v,m) assert(v,m) end
            function file() return nil end;function photo() error('unexpected capture') end
            app={draw=function() end}
            function press(rect) pressed=rect.id end
            function cell(q,r) clicked={q=q,r=r} end
        ''' + 'function battlePilot()' + body)

    def test_normal_battle_pilot_selects_owned_weapon_then_actual_legal_target(self):
        self.battle_pilot()
        self.lua.execute('''
            assert(battlePilot() and pressed=='sword' and stopped)
            assert(enemy.hp==18 and unit.hp==17 and campaign.players.host.ammo.rocks==8)
            battle.phase='target';battle.chosenItemId=campaign.players.host.itemSlots.equipment[1].id
            battle.chosenWeapon='frontier-short-sword';pressed=nil
            assert(battlePilot() and clicked.q==enemy.q and clicked.r==enemy.r and hostAttacks==1)
            assert(enemy.hp==18) -- Only emits the ordinary target click.
        ''')

    def test_normal_battle_pilot_moves_only_to_production_reachable_space(self):
        self.battle_pilot()
        self.lua.execute('''
            enemy.q=9;enemy.r=6
            assert(battlePilot() and pressed=='move' and clicked)
            assert(Rules.canMove(battle,unit,clicked.q,clicked.r,unit.move))
            assert(unit.q==1 and unit.r==1 and enemy.hp==18)
            pressed=nil;clicked=nil;battle.moveUsed=true;battle.phase='action'
            assert(battlePilot() and pressed=='end' and not clicked)
        ''')


if __name__ == '__main__':
    unittest.main()
