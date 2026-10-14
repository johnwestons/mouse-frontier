"""Combined production session boundaries over fake transport, not device soak."""
import unittest
import test_coop_local_play_behavior as application_tests


class NetworkBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.harness = application_tests.LocalPlayTests()
        self.harness.setUp()
        self.harness.enable_trade()
        self.lua = self.harness.lua
        self.lua.execute('''
            P=require('game.net.protocol')
            lab.classifier=function(bytes)
                for _,channel in ipairs({P.CONTROL,P.STATE,P.REALTIME})do
                    local m=P.decode(bytes,channel)
                    if m then return m.command or m.type end
                end
            end
            function noPurchasesSince(index)
                for i=index+1,#lab.log do assert(lab.log[i].kind~='merchant.buy','reconnect blindly replayed purchase')end
            end
            function rejoin()
                assert(guest:join());step(18)
                assert(guest.phase=='connected',guest.error or guest.phase)
                assert(guest.network.status=='ready' and not guest.network.pendingCommand)
                assert(not guest.network.receiver and not guest.network.pendingSnapshot and not host.network.link.transfer)
            end
        ''')

    def tearDown(self):
        self.harness.tearDown()

    def test_disconnect_before_delayed_purchase_dispatch_does_not_retry_or_spend_on_rejoin(self):
        self.lua.execute('''
            ready();motionReady();local args,expected=tradeArgs('merchant.buy',1)
            local before=Schema.copy(data);local stock=Schema.copy(layout.tradeStock)
            lab:delayNext('client_to_host',1,30)
            local id=assert(guest.network:submitCommand('merchant.buy',args,data.coop.sceneEpoch,expected))
            local old=guest.network;assert(old.pendingCommand and not old.lastCommandResult)
            guest:stop();host:update();local start=#lab.log
            rejoin();step(35);noPurchasesSince(start)
            assert(old.closed and old.transport.closed and guest.network~=old)
            assert(data.scrap==before.scrap and data.players.companion.inventory[3]==nil)
            assert(guest.replica.data.scrap==before.scrap and guest.replica.data.players.companion.inventory[3]==nil)
            assert(not service.requests.companion or not service.requests.companion.cache[id])
            assert(guest.network.nextRequestId==id)
            local codec=require('game.net.codec');assert(codec.encode(layout.tradeStock)==codec.encode(stock))
        ''')

    def test_disconnect_after_committed_purchase_before_reply_reconciles_baseline_without_retry(self):
        self.lua.execute('''
            ready();motionReady();local args,expected=tradeArgs('merchant.buy',1);local price=args.quotedPrice
            local hostItem=data.players.host.itemSlots.equipment[1].id
            local transport=host.network.transport;local send=transport.send;local delayed=0
            transport.send=function(self,peer,bytes,channel,reliable)
                local m=P.decode(bytes,channel)
                if m and m.type=='command_result' and m.command=='merchant.buy'then
                    delayed=delayed+1;lab:delayNext('host_to_client',1,30)
                end
                return send(self,peer,bytes,channel,reliable)
            end
            local id=assert(guest.network:submitCommand('merchant.buy',args,data.coop.sceneEpoch,expected))
            step(2);local old=guest.network
            assert(delayed==1 and old.pendingCommand and not old.lastCommandResult)
            assert(data.scrap==200-price and saved.scrap==200-price)
            local bought=data.players.companion.itemSlots.inventory[3].id
            assert(saved.players.companion.itemSlots.inventory[3].id==bought)
            local revision=data.coop.revision
            guest:stop();host:update();local start=#lab.log
            transport.send=send;rejoin();step(35);noPurchasesSince(start)
            assert(old.closed and guest.network~=old and guest.network.nextRequestId==id+1)
            assert(data.scrap==200-price and data.coop.revision==revision)
            assert(guest.replica.data.players.companion.itemSlots.inventory[3].id==bought)
            assert(guest.replica.data.scrap==200-price and data.players.host.itemSlots.equipment[1].id==hostItem)
            assert(not guest.network.lastCommandResult,'old delayed receipt became a new connection result')
        ''')

    def test_eighty_authenticated_join_leave_cycles_bound_receipts_and_preserve_owned_state(self):
        self.lua.execute('''
            ready();motionReady();local before=Schema.copy(data.players)
            local identity=Schema.copy(data.coop.network);local firstGeneration=host.generation
            local itemCounter=data.itemIdentity.next;local requests=0
            for cycle=1,80 do
                local args,expected=tradeArgs('merchant.buy',1);args.quotedPrice=args.quotedPrice+1
                local reply=tradeAct('merchant.buy',1,args,expected)
                assert(not reply.ok and reply.reason=='quote_changed');requests=requests+1
                local history=service.requests.companion;local count=0
                for _ in pairs(history.cache)do count=count+1 end
                assert(count<=64 and #history.order<=64)
                guest:stop();host:update();assert(not service.bindings.companion)
                rejoin();motionReady()
                assert(data.coop.network.campaignId==identity.campaignId and data.coop.network.companionId==identity.companionId)
                assert(data.scrap==200 and data.itemIdentity.next==itemCounter)
                assert(data.players.host.itemSlots.equipment[1].id==before.host.itemSlots.equipment[1].id)
                assert(data.players.companion.itemSlots.equipment[1].id==before.companion.itemSlots.equipment[1].id)
                assert(data.players.companion.inventory[3]==nil and not guest.network.pendingCommand)
            end
            assert(requests==80 and #service.requests.companion.order==64)
            assert(host.generation>=firstGeneration+80 and guest.network.nextRequestId==81)
            step(20);assert(lab:pendingFor('host')==0 and lab:pendingFor('client',1)==0 and #lab.scheduled==0)
            -- Harness log/allLinks intentionally record every cycle; these are
            -- instrumentation, not evidence of production process memory use.
        ''')

    def test_connected_session_motion_converges_under_loss_duplication_jitter_and_overtaking(self):
        self.lua.execute('''
            ready();motionReady();local Wire=require('game.net.movement');local Prediction=require('game.coop_prediction')
            local function move(_,_,ox,oy,x,y)return math.max(80,math.min(900,x)),math.max(100,math.min(600,y))end
            host.motion.context.move=move
            local predictor=Prediction.new({clock=function()return clock end,data=function()return guest.replica.data end,move=move})
            predictor:reset(data.coop.sceneEpoch,host.motion.actor,hostRuntime.player,host.motion.motionId)
            assert(predictor:receive(guest.motionFrame,true))
            local hostTransport,clientTransport=host.network.transport,guest.network.transport
            local downstream,upstream=hostTransport.send,clientTransport.sendToServer
            local sentDown,sentUp=0,0
            hostTransport.send=function(self,peer,bytes,channel,reliable)
                local m=P.decode(bytes,channel)
                if m and m.type=='motion'then
                    sentDown=sentDown+1
                    assert(not reliable and channel==P.REALTIME)
                    assert(lab:queueAction('host_to_client',1,{drop=sentDown%6==0,
                        delay=sentDown%3==0 and 8 or sentDown%2,duplicates=sentDown%7==0 and 1 or 0}))
                end
                return downstream(self,peer,bytes,channel,reliable)
            end
            clientTransport.sendToServer=function(self,bytes,channel,reliable)
                local m=P.decode(bytes,channel)
                if m and m.type=='movement'then
                    sentUp=sentUp+1
                    assert(not reliable and channel==P.REALTIME)
                    assert(lab:queueAction('client_to_host',1,{drop=sentUp%5==0,
                        delay=sentUp%3==0 and 7 or sentUp%2,duplicates=sentUp%11==0 and 1 or 0}))
                end
                return upstream(self,bytes,channel,reliable)
            end
            local before=Schema.copy(data.players);local resources=Schema.copy(data.resources);local start=clock
            local sequence=0;local serial=guest.motionFrame.serial;local maxError,maxPending=0,0
            for tick=1,1200 do
                clock=start+tick/60;local elapsed=tick/60
                local input={x=elapsed<2 and 1 or elapsed<3 and -1 or 0,y=0,sprint=false}
                if tick%3==1 then
                    sequence=sequence+1;assert(predictor:sent(sequence,input))
                    assert(guest.network:sendMovement(sequence,data.coop.sceneEpoch,input.x*1000,0,false,host.motion.motionId))
                end
                host:update();guest:update();lab:advanceSteps(1)
                local frame=guest.motionFrame
                if frame.serial~=serial then
                    local ok,reason=predictor:receive(frame,true);assert(ok~=nil,reason);serial=frame.serial
                end
                assert(predictor:update(input,true))
                assert(guest.phase=='connected' and host.phase=='hosting')
                assert(predictor.display.x>=80 and predictor.display.x<=900)
                maxError=math.max(maxError,math.abs(predictor.display.x-host.motion.actor.x))
                maxPending=math.max(maxPending,lab:pendingFor('host'),lab:pendingFor('client',1),#lab.scheduled)
                assert(#predictor.sampleOrder<=Prediction.MAX_SAMPLES and #predictor.history<=Prediction.MAX_HISTORY)
            end
            assert(sentUp==400 and sentDown>150 and maxError<160 and maxPending<64)
            assert(math.abs(predictor.display.x-host.motion.actor.x)<.05 and not host.motion.actor.moving and not predictor.actor.moving)
            local codec=require('game.net.codec')
            assert(codec.encode(data.resources)==codec.encode(resources))
            assert(data.players.host.itemSlots.equipment[1].id==before.host.itemSlots.equipment[1].id)
            assert(data.players.companion.itemSlots.equipment[1].id==before.companion.itemSlots.equipment[1].id)
            assert(hostRuntime.player.x==200 and hostRuntime.player.y==250)
            assert(data.players.companion.playerX==host.motion.actor.x and data.players.companion.playerY==host.motion.actor.y)
            hostTransport.send=downstream;clientTransport.sendToServer=upstream
            step(20);assert(#lab.scheduled==0 and lab:pendingFor('host')==0 and lab:pendingFor('client',1)==0)
            impairmentMetrics={seconds=20,movementSamples=sentUp,motionFrames=sentDown,maxError=maxError,maxPending=maxPending}
        ''')


if __name__ == '__main__':
    unittest.main()
